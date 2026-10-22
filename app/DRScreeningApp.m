function DRScreeningApp()
% DRSCREENINGAPP  Programmatic MATLAB app for the judge demo.
%   Run: DRScreeningApp()
%
%   Pipeline: quality check -> enhancement -> CNN classification -> Grad-CAM
%   heatmap -> lesion candidate map -> consistency check -> optional TinyFish
%   online support -> two-page PDF report (Print Report (PDF) button).
%
%   Requires models/dr_classifier_binary.mat (or update MODEL_PATH below).
%
%   Optional TinyFish features (bring your own key: click "Set TinyFish API
%   key" or setenv('TINYFISH_API_KEY', ...)). For non-low-risk results or when
%   the CNN and the lesion evidence disagree:
%     1. Referral resources (Search API)               -> getReferralInfo
%     2. Human-review evidence from PubMed / AIOS      -> ishtiLiteratureCheck
%     3. PM-JAY empanelled eye hospitals (Agent API)   -> ishtiFindPMJAYHospitals
%   Only a generic topic and the camp's district/state/pincode are sent.
%   No images or patient data leave MATLAB. The app works fully without a key.

    appDir = fileparts(mfilename('fullpath'));
    for sub = {fullfile('..', 'src'), fullfile('..', 'src', 'tinyfish')}
        d = fullfile(appDir, sub{1});
        if isfolder(d), addpath(d); end
    end

    MODEL_PATH = fullfile('models', 'dr_classifier_binary.mat');

    fig = uifigure('Name', 'Explainable AI - DR Screening Prototype', ...
        'Position', [60 60 1010 650]);

    uilabel(fig, 'Text', 'Explainable AI for Diabetic Retinopathy Screening', ...
        'FontSize', 18, 'FontWeight', 'bold', 'Position', [30 605 700 30]);

    axImg = uiaxes(fig, 'Position', [30 250 250 330]);
    title(axImg, 'Uploaded Fundus Image');
    axCam = uiaxes(fig, 'Position', [295 250 250 330]);
    title(axCam, 'Grad-CAM Heatmap');
    axLes = uiaxes(fig, 'Position', [560 250 250 330]);
    title(axLes, 'Lesion Candidates');

    resultArea = uitextarea(fig, 'Position', [30 30 950 200], ...
        'Editable', 'off', 'FontSize', 13, ...
        'Value', {'Upload a fundus image to begin screening.'});

    uploadBtn = uibutton(fig, 'Text', 'Upload Fundus Image', ...
        'Position', [830 560 150 40], 'FontSize', 13);

    uilabel(fig, 'Text', 'Camp location (referral search):', ...
        'FontSize', 11, 'Position', [830 525 175 22]);
    cityField = uieditfield(fig, 'text', 'Position', [830 495 150 28], ...
        'Placeholder', 'District, e.g. Pune');
    stateField = uieditfield(fig, 'text', 'Position', [830 465 150 28], ...
        'Placeholder', 'State (optional)');
    pinField = uieditfield(fig, 'text', 'Position', [830 435 150 28], ...
        'Placeholder', 'Pincode (optional)');

    keyBtn = uibutton(fig, 'Text', 'Set TinyFish API key', ...
        'Position', [830 390 150 30], 'FontSize', 11);
    keyBtn.ButtonPushedFcn = @(btn, event) onSetKey();

    exportBtn = uibutton(fig, 'Text', 'Print Report (PDF)', ...
        'Position', [830 335 150 40], 'FontSize', 13, 'FontWeight', 'bold', ...
        'Enable', 'off');
    exportBtn.ButtonPushedFcn = @(btn, event) onExport();

    netHolder = struct('net', []);
    state = struct('imgPath', '', 'result', [], 'les', [], 'extra', {{}});

    uploadBtn.ButtonPushedFcn = @(btn, event) onUpload();

    function onSetKey()
        a = inputdlg({['Paste your own TinyFish API key ' ...
            '(agent.tinyfish.ai/api-keys). It is kept for this MATLAB ' ...
            'session only and never saved to a file.']}, ...
            'TinyFish API key', [1 70]);
        if ~isempty(a) && ~isempty(strtrim(a{1}))
            setenv('TINYFISH_API_KEY', strtrim(a{1}));
            uialert(fig, 'TinyFish key set for this MATLAB session.', ...
                'TinyFish', 'Icon', 'success');
        end
    end

    function onUpload()
        [file, path] = uigetfile({'*.png;*.jpg;*.jpeg', 'Fundus Images'});
        if isequal(file, 0)
            return;
        end
        imgPath = fullfile(path, file);
        exportBtn.Enable = 'off';

        if isempty(netHolder.net)
            if ~isfile(MODEL_PATH)
                uialert(fig, sprintf('Model not found at %s. Run trainDRClassifier first.', ...
                    MODEL_PATH), 'Model Missing');
                return;
            end
            loaded = load(MODEL_PATH, 'net');
            netHolder.net = loaded.net;
        end

        resultArea.Value = {'Running pipeline...'};
        drawnow;

        img = imread(imgPath);
        imshow(img, 'Parent', axImg);
        cla(axCam); cla(axLes);

        result = runPipeline(imgPath, netHolder.net, '');

        if result.rejected
            resultArea.Value = {'IMAGE REJECTED', '', result.reason};
            return;
        end

        % --- lesion candidate map + heatmap overlay ---
        les = [];
        lesionMsg = '';
        try
            les = ishtiLesionAnalysis(img);
            imshow(les.overlay, 'Parent', axLes);
        catch ME
            lesionMsg = ['Lesion analysis unavailable: ' ME.message];
        end
        try
            if isempty(les), error('no lesion struct'); end
            imshow(ishtiHeatOverlay(les.rgb, result.gradcamMap, 0.5), 'Parent', axCam);
        catch
            imagesc(axCam, result.gradcamMap);
            colormap(axCam, 'jet');
            axis(axCam, 'off');
        end

        [conflict, note] = ishtiConflictType(result, les);

        lines = {
            sprintf('Classification: %s', result.label), ...
            sprintf('Confidence: %.1f%%', result.confidence), ...
            sprintf('Risk: %s', result.riskLabel), ...
            '', ...
            sprintf('Image Quality: Gradeable (enhancement applied: %s)', ...
                mat2str(result.qualityReport.enhanced)), ...
            sprintf('Vessel density: %.2f%%', result.structOut.vesselDensity*100)
        };
        if ~isempty(les)
            lines = [lines, {sprintf('Lesion candidates: %d red-type, %d bright-type (burden: %s)', ...
                les.nRed, les.nBright, les.burden), char(note)}];
        elseif ~isempty(lesionMsg)
            lines = [lines, {lesionMsg}];
        end
        lines = [lines, {'', ...
            'NOTE: Prototype demo. Risk label is a confidence-based proxy,', ...
            'not a clinically validated ICDR 0-4 grade.'}];

        % --- Optional online support for non-low-risk or discordant results ---
        extra = {};
        needsLookup = ~startsWith(string(result.riskLabel), "Low") || ~isempty(conflict);
        if needsLookup
            resultArea.Value = [lines, {'', ...
                'Looking up referral resources and evidence (can take a minute)...'}];
            drawnow;
            if isempty(conflict), conflict = conflictTypeFor(result); end
            extra = [referralLines(cityField.Value), ...
                tinyfishLines(conflict, cityField.Value, stateField.Value, pinField.Value)];
            lines = [lines, extra];
        end

        state.imgPath = imgPath;
        state.result  = result;
        state.les     = les;
        state.extra   = extra;
        resultArea.Value = lines;
        exportBtn.Enable = 'on';
    end

    function onExport()
        % One click: generate the PDF, save it to Downloads, and open it.
        if isempty(state.result), return; end
        [~, nm] = fileparts(state.imgPath);
        home = getenv('USERPROFILE');
        if isempty(home), home = getenv('HOME'); end
        outDir = fullfile(home, 'Downloads');
        if isempty(home) || ~isfolder(outDir), outDir = fullfile(pwd, 'reports'); end
        pdfPath = fullfile(outDir, ['DR_Report_' nm '_' datestr(now, 'yyyymmdd_HHMMSS') '.pdf']);
        dlg = uiprogressdlg(fig, 'Title', 'Report', ...
            'Message', 'Generating PDF report...', 'Indeterminate', 'on');
        try
            out = generateScreeningPDF(state.imgPath, state.result, state.les, ...
                state.extra, pdfPath, fullfile(pwd, 'reports'));
            close(dlg);
            uialert(fig, sprintf('Report downloaded:\n%s', out.pdf), ...
                'Report ready', 'Icon', 'success');
            try, open(out.pdf); catch, end %#ok<NOCOMMA>
        catch ME
            close(dlg);
            uialert(fig, ['PDF generation failed: ' ME.message], 'Report error');
        end
    end

    function out = referralLines(city)
        % Builds the referral section; never throws.
        out = {''};
        try
            info = getReferralInfo(city, 3);
        catch ME
            info = struct('ok', false, 'message', string(ME.message), 'items', []);
        end
        if info.ok
            out{end+1} = 'Referral resources (TinyFish Search, verify before use):';
            for k = 1:numel(info.items)
                out{end+1} = char(sprintf('  %d. %s', k, info.items(k).title));
                out{end+1} = char(sprintf('     %s', info.items(k).url));
            end
        else
            out{end+1} = char(info.message);
        end
    end

    function out = tinyfishLines(conflict, district, state_, pin)
        % Human-review evidence (PubMed/AIOS) + PM-JAY eye hospitals.
        % Never throws; skipped quietly when no key is set.
        out = {''};
        key = tinyfishKey(false);
        if isempty(key)
            out{end+1} = 'Tip: click "Set TinyFish API key" to add evidence lookup and PM-JAY eye-hospital search.';
            return;
        end
        hasLocation = ~isempty(strtrim(district)) || ~isempty(strtrim(pin));
        try
            tf = ishtiTinyFishReport(conflict, district, ...
                'Pincode', pin, 'State', state_, 'Key', key, ...
                'SkipHospitals', ~hasLocation);
            out = [out, tf.lines(:)'];
        catch ME
            out{end+1} = ['TinyFish extras unavailable: ' ME.message];
        end
        if ~hasLocation
            out{end+1} = 'Enter a district or pincode to also find PM-JAY empanelled eye hospitals.';
        end
    end
end

function c = conflictTypeFor(result)
% Fallback generic topic when no lesion evidence is available.
    lbl = lower(string(result.label));
    isDR = (contains(lbl, "dr") || contains(lbl, "retinopathy")) && ~contains(lbl, "no");
    if isDR, c = 'ReferableConfirmed'; else, c = 'GradeZeroLesionPresent'; end
end
