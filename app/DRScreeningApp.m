function DRScreeningApp()
% DRSCREENINGAPP  Phase 7: programmatic MATLAB app for the judge demo.
%   Built with uifigure (not App Designer .mlapp) so it's plain
%   version-controllable code. Run: DRScreeningApp()
%
%   Requires models/dr_classifier_binary.mat (trained in Phase 4) to
%   exist and be on the MATLAB path, or update MODEL_PATH below.
%
%   Optional TinyFish features (bring your own key, click "Set TinyFish
%   API key" or setenv('TINYFISH_API_KEY', ...)). For non-low-risk results:
%     1. Referral resources (Search API)                 -> getReferralInfo
%     2. Human-review evidence from PubMed / AIOS        -> ishtiLiteratureCheck
%     3. PM-JAY empanelled eye hospitals near the camp   -> ishtiFindPMJAYHospitals
%   Only a generic topic and the camp's district/state/pincode are sent.
%   No images or patient data leave MATLAB. The app works fully without a key.

    % Make the TinyFish helper functions visible regardless of current folder
    appDir = fileparts(mfilename('fullpath'));
    for sub = {fullfile('..', 'src'), fullfile('..', 'src', 'tinyfish')}
        d = fullfile(appDir, sub{1});
        if isfolder(d), addpath(d); end
    end

    MODEL_PATH = fullfile('models', 'dr_classifier_binary.mat');

    fig = uifigure('Name', 'Explainable AI - DR Screening Prototype', ...
        'Position', [100 100 950 650]);

    uilabel(fig, 'Text', 'Explainable AI for Diabetic Retinopathy Screening', ...
        'FontSize', 18, 'FontWeight', 'bold', 'Position', [30 600 700 30]);

    axImg = uiaxes(fig, 'Position', [30 250 350 330]);
    title(axImg, 'Uploaded Fundus Image');

    axCam = uiaxes(fig, 'Position', [400 250 350 330]);
    title(axCam, 'Grad-CAM Attention');

    resultArea = uitextarea(fig, 'Position', [30 30 890 200], ...
        'Editable', 'off', 'FontSize', 13, ...
        'Value', {'Upload a fundus image to begin screening.'});

    uploadBtn = uibutton(fig, 'Text', 'Upload Fundus Image', ...
        'Position', [770 560 150 40], 'FontSize', 13);

    uilabel(fig, 'Text', 'Camp location (referral search):', ...
        'FontSize', 11, 'Position', [770 525 175 22]);
    cityField = uieditfield(fig, 'text', 'Position', [770 495 150 28], ...
        'Placeholder', 'District, e.g. Pune');
    stateField = uieditfield(fig, 'text', 'Position', [770 465 150 28], ...
        'Placeholder', 'State (optional)');
    pinField = uieditfield(fig, 'text', 'Position', [770 435 150 28], ...
        'Placeholder', 'Pincode (optional)');

    keyBtn = uibutton(fig, 'Text', 'Set TinyFish API key', ...
        'Position', [770 390 150 30], 'FontSize', 11);
    keyBtn.ButtonPushedFcn = @(btn, event) onSetKey();

    netHolder = struct('net', []); % simple closure-captured state

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

        result = runPipeline(imgPath, netHolder.net, '');

        if result.rejected
            resultArea.Value = {'IMAGE REJECTED', '', result.reason};
            cla(axCam);
            return;
        end

        imagesc(axCam, result.gradcamMap);
        colormap(axCam, 'jet');
        axis(axCam, 'off');

        lines = {
            sprintf('Classification: %s', result.label), ...
            sprintf('Confidence: %.1f%%', result.confidence), ...
            sprintf('Risk: %s', result.riskLabel), ...
            '', ...
            sprintf('Image Quality: Gradeable (enhancement applied: %s)', ...
                mat2str(result.qualityReport.enhanced)), ...
            sprintf('Vessel density: %.2f%%', result.structOut.vesselDensity*100), ...
            '', ...
            'NOTE: Prototype demo. Risk label is a confidence-based proxy,', ...
            'not a clinically validated ICDR 0-4 grade.'
        };

        % --- Optional TinyFish lookups for non-low-risk results ---
        if ~startsWith(string(result.riskLabel), "Low")
            resultArea.Value = [lines, {'', ...
                'Looking up referral resources and evidence (can take a minute)...'}];
            drawnow;
            lines = [lines, referralLines(cityField.Value)];
            lines = [lines, tinyfishLines(result, cityField.Value, ...
                stateField.Value, pinField.Value)];
        end

        resultArea.Value = lines;
    end

    function out = referralLines(city)
        % Builds the referral section; never throws, so the app keeps working
        % offline or without an API key.
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

    function out = tinyfishLines(result, district, state, pin)
        % Human-review evidence (PubMed/AIOS) + PM-JAY eye hospitals.
        % Never throws; silently skipped when no key is set.
        out = {''};
        key = tinyfishKey(false);          % no pop-up in the middle of a screening
        if isempty(key)
            out{end+1} = 'Tip: click "Set TinyFish API key" to add evidence lookup and PM-JAY eye-hospital search.';
            return;
        end
        hasLocation = ~isempty(strtrim(district)) || ~isempty(strtrim(pin));
        try
            tf = ishtiTinyFishReport(conflictTypeFor(result), district, ...
                'Pincode', pin, 'State', state, 'Key', key, ...
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
% Maps the current binary pipeline output to a generic, PHI-free topic.
% This is a proxy: DR predicted -> referral guidance; "No DR" but a
% non-low risk (uncertain) -> grade-vs-lesion discordance evidence.
    lbl = lower(string(result.label));
    isDR = (contains(lbl, "dr") || contains(lbl, "retinopathy")) && ~contains(lbl, "no");
    if isDR
        c = 'ReferableConfirmed';
    else
        c = 'GradeZeroLesionPresent';
    end
end
