function out = generateScreeningPDF(imgPath, result, les, extraLines, pdfPath, pngDir)
%GENERATESCREENINGPDF  Two-page PDF screening report (no extra toolbox needed).
%   out = generateScreeningPDF(imgPath, result, les, extraLines, pdfPath)
%
%   imgPath    path of the fundus image (used for the file name only)
%   result     struct returned by runPipeline
%   les        struct from ishtiLesionAnalysis (computed here if empty)
%   extraLines cellstr with referral / TinyFish lines (can be {})
%   pdfPath    output .pdf (default: reports/DR_Report_<timestamp>.pdf)
%   pngDir     folder for the saved heatmap/lesion PNGs (default: same as PDF)
%
%   Page 1: summary, original | Grad-CAM heatmap | lesion map, lesion analysis.
%   Page 2: referral + evidence (TinyFish), suggested next step, limitations.
%   Also saves <name>_fundus.png, <name>_heatmap.png, <name>_lesions.png.
%   Uses exportgraphics (MATLAB R2020a or newer).

    if nargin < 3 || isempty(les), les = ishtiLesionAnalysis(imgPath); end
    if nargin < 4 || isempty(extraLines), extraLines = {}; end
    extraLines = cellstr(extraLines);
    if nargin < 5 || isempty(pdfPath)
        pdfPath = fullfile(pwd, 'reports', ['DR_Report_' datestr(now, 'yyyymmdd_HHMMSS') '.pdf']);
    end
    pdfPath = char(pdfPath);
    outDir = fileparts(pdfPath);
    if isempty(outDir), outDir = pwd; pdfPath = fullfile(outDir, pdfPath); end
    if ~isfolder(outDir), mkdir(outDir); end
    if nargin < 6 || isempty(pngDir), pngDir = outDir; end
    if ~isfolder(pngDir), mkdir(pngDir); end
    [~, base] = fileparts(pdfPath);
    [~, imgName, imgExt] = fileparts(char(imgPath));

    % ---------- values ----------
    label = char(string(sget(result, 'label', 'n/a')));
    conf  = sget(result, 'confidence', NaN);
    risk  = char(string(sget(result, 'riskLabel', 'n/a')));
    if isnumeric(conf) && isfinite(conf), confStr = sprintf('%.1f%%', conf); else, confStr = 'n/a'; end
    qr = sget(result, 'qualityReport', struct());
    enh = sget(qr, 'enhanced', []);
    if isempty(enh), qualStr = 'Gradeable'; else, qualStr = ['Gradeable (enhancement applied: ' mat2str(logical(enh)) ')']; end
    so = sget(result, 'structOut', struct());
    vd = sget(so, 'vesselDensity', NaN);
    caseId  = ['DR-' datestr(now, 'yyyymmdd-HHMMSS')];
    dateStr = datestr(now, 'dd mmm yyyy, HH:MM');
    [conflict, note] = ishtiConflictType(result, les);
    riskLow = startsWith(string(risk), "Low");

    % ---------- images ----------
    heat = [];
    cam = sget(result, 'gradcamMap', []);
    if ~isempty(cam)
        try, heat = ishtiHeatOverlay(les.rgb, cam, 0.5); catch, heat = []; end
    end
    imwrite(les.rgb,     fullfile(pngDir, [base '_fundus.png']));
    imwrite(les.overlay, fullfile(pngDir, [base '_lesions.png']));
    if ~isempty(heat), imwrite(heat, fullfile(pngDir, [base '_heatmap.png'])); end

    % ---------- page geometry (A4 proportions, drawn at 75% size) ----------
    W = 8.27; H = 11.69; SC = 0.75;
    navy = [0.07 0.22 0.42]; gray = [0.35 0.35 0.35];
    if riskLow, riskCol = [0.18 0.60 0.34]; else, riskCol = [0.80 0.28 0.18]; end

    % =============================== PAGE 1 ===============================
    [f, ax] = newPage(W, H, SC);
    put  = @(x, y, s, fs, varargin) text(ax, x, H - y, s, 'FontSize', fs * SC, ...
        'Interpreter', 'none', 'VerticalAlignment', 'top', ...
        'HorizontalAlignment', 'left', 'Clipping', 'off', varargin{:});
    rect = @(x, y, w, h, col) rectangle(ax, 'Position', [x, H - y - h, w, h], ...
        'FaceColor', col, 'EdgeColor', 'none');

    rect(0, 0, W, 1.0, navy);
    put(0.5, 0.22, 'DR-Ishti Screening Report', 20, 'Color', 'w', 'FontWeight', 'bold');
    put(0.5, 0.68, 'Explainable AI for Diabetic Retinopathy Screening  |  Research prototype', 9.5, 'Color', [0.85 0.9 1]);

    put(0.5, 1.2,  sprintf('Case ID: %s', caseId), 10, 'FontWeight', 'bold');
    put(0.5, 1.45, sprintf('Generated: %s', dateStr), 9, 'Color', gray);
    put(0.5, 1.65, sprintf('Source image: %s%s', imgName, imgExt), 9, 'Color', gray);
    put(0.5, 1.85, 'Model: MATLAB deep learning classifier trained on APTOS 2019 (binary DR / No DR)', 9, 'Color', gray);

    rect(0.5, 2.25, 7.27, 1.1, [0.95 0.96 0.98]);
    rect(0.5, 2.25, 0.12, 1.1, riskCol);
    put(0.8, 2.35, ['Classification: ' label], 13, 'FontWeight', 'bold');
    put(0.8, 2.68, sprintf('Confidence: %s        Risk level: %s', confStr, risk), 11);
    put(0.8, 3.0,  ['Image quality: ' qualStr], 9, 'Color', gray);

    % three images side by side
    y0 = 3.6; wImg = 2.3; gap = 0.185;
    asp = size(les.rgb, 1) / size(les.rgb, 2);
    hImg = min(2.6, wImg * asp);
    imgs = {les.rgb, heat, les.overlay};
    caps = {'Fundus image', 'Grad-CAM heatmap overlay', 'Lesion candidate map'};
    subs = {'Uploaded image (resized)', 'Warm colours: regions that most influenced the model', 'Cyan: red-lesion candidates  |  Yellow: bright-lesion candidates'};
    for k = 1:3
        x = 0.5 + (k - 1) * (wImg + gap);
        axk = axes(f, 'Units', 'normalized', 'Position', [x / W, (H - y0 - hImg) / H, wImg / W, hImg / H]);
        im = imgs{k};
        if isempty(im), im = uint8(235 * ones(10, 10, 3)); end
        image(axk, im); axis(axk, 'image'); axis(axk, 'off');
        put(x, y0 + hImg + 0.06, caps{k}, 9, 'FontWeight', 'bold');
        for ln = 1:numel(wrapText(subs{k}, 40))
            wl = wrapText(subs{k}, 40);
            put(x, y0 + hImg + 0.26 + (ln - 1) * 0.15, wl{ln}, 7, 'Color', gray);
        end
    end
    if isempty(heat)
        put(0.5 + wImg + gap + 0.3, y0 + hImg / 2, 'Heatmap unavailable', 9, 'Color', gray);
    end

    % lesion analysis
    y = y0 + hImg + 0.9;
    put(0.5, y, 'Lesion and structure analysis', 11.5, 'FontWeight', 'bold', 'Color', navy);
    plot(ax, [0.5 7.77], [H - y - 0.27, H - y - 0.27], 'Color', navy, 'LineWidth', 0.75);
    y = y + 0.38;
    items = { ...
        sprintf('Red-lesion candidates (microaneurysm / haemorrhage-like): %d', les.nRed), ...
        sprintf('Bright-lesion candidates (exudate-like): %d', les.nBright), ...
        sprintf('Lesion area within the retina: %.2f %%', les.areaPct), ...
        sprintf('Estimated lesion burden: %s', les.burden), ...
        sprintf('Retinal vessel density: %s', numOrNA(vd * 100, '%.2f %%'))};
    for k = 1:numel(items)
        put(0.6, y, ['-  ' items{k}], 9.5); y = y + 0.22;
    end

    y = y + 0.15;
    if isempty(conflict) || strncmp(note, 'Classifier output', 17) || strncmp(note, 'Classifier flags', 16)
        boxCol = [0.90 0.96 0.92];
    else
        boxCol = [1.00 0.94 0.84];
    end
    nl = wrapText(['Consistency check: ' note], 100);
    rect(0.5, y, 7.27, 0.2 + 0.2 * numel(nl), boxCol);
    for k = 1:numel(nl), put(0.62, y + 0.1 + (k - 1) * 0.2, nl{k}, 9, 'FontWeight', 'bold'); end
    y = y + 0.4 + 0.2 * numel(nl);

    put(0.5, y, 'How to read this report', 10, 'FontWeight', 'bold', 'Color', navy); y = y + 0.25;
    hw = wrapText(['The heatmap comes from the deep learning model and shows where it looked. ' ...
        'The lesion map comes from a separate image-processing step and marks candidate lesions for the reviewing clinician. ' ...
        'Neither is a diagnosis.'], 105);
    for k = 1:numel(hw), put(0.5, y, hw{k}, 8.5, 'Color', gray); y = y + 0.18; end
    footer(put, H, 1, 2);
    exportPage(f, pdfPath, false);
    close(f);

    % =============================== PAGE 2 ===============================
    [f, ax] = newPage(W, H, SC);
    put  = @(x, y, s, fs, varargin) text(ax, x, H - y, s, 'FontSize', fs * SC, ...
        'Interpreter', 'none', 'VerticalAlignment', 'top', ...
        'HorizontalAlignment', 'left', 'Clipping', 'off', varargin{:});
    rect = @(x, y, w, h, col) rectangle(ax, 'Position', [x, H - y - h, w, h], ...
        'FaceColor', col, 'EdgeColor', 'none');
    rect(0, 0, W, 0.8, navy);
    put(0.5, 0.2, 'Referral and evidence support', 16, 'Color', 'w', 'FontWeight', 'bold');
    put(0.5, 0.55, sprintf('Case %s', caseId), 9, 'Color', [0.85 0.9 1]);

    y = 1.1;
    put(0.5, y, 'Online support (TinyFish Search and Agent APIs)', 11.5, 'FontWeight', 'bold', 'Color', navy);
    plot(ax, [0.5 7.77], [H - y - 0.27, H - y - 0.27], 'Color', navy, 'LineWidth', 0.75);
    y = y + 0.38;
    while ~isempty(extraLines) && isempty(strtrim(extraLines{1})), extraLines(1) = []; end
    if isempty(extraLines)
        extraLines = {'No online lookups were run for this case (no TinyFish API key set, or a low-risk result with consistent findings).'};
    end
    shown = 0; maxLines = 34; truncated = false;
    for k = 1:numel(extraLines)
        wl = wrapText(extraLines{k}, 100);
        for j = 1:numel(wl)
            if shown >= maxLines, truncated = true; break; end
            put(0.5, y, wl{j}, 8.5); y = y + 0.19; shown = shown + 1;
        end
        if truncated, break; end
    end
    if truncated, put(0.5, y, '(additional lines omitted)', 8, 'Color', gray); y = y + 0.19; end

    y = max(y + 0.3, 7.6);
    put(0.5, y, 'Suggested next step', 11.5, 'FontWeight', 'bold', 'Color', navy);
    plot(ax, [0.5 7.77], [H - y - 0.27, H - y - 0.27], 'Color', navy, 'LineWidth', 0.75);
    y = y + 0.38;
    if ~riskLow || ~isempty(conflict)
        step = ['Refer to an ophthalmologist for a dilated eye examination. The clinician should review the ' ...
            'highlighted regions and the evidence above. Confirm PM-JAY empanelment before referring.'];
    else
        step = 'No referable finding was flagged by this prototype. Follow the screening programme''s routine re-screening interval.';
    end
    sl = wrapText(step, 100);
    for k = 1:numel(sl), put(0.5, y, sl{k}, 9.5); y = y + 0.21; end

    y = y + 0.35;
    put(0.5, y, 'Limitations', 11.5, 'FontWeight', 'bold', 'Color', navy);
    plot(ax, [0.5 7.77], [H - y - 0.27, H - y - 0.27], 'Color', navy, 'LineWidth', 0.75);
    y = y + 0.38;
    lims = { ...
        'Prototype for research and education. Not a medical device and not clinically validated.', ...
        'Binary classifier (DR / No DR) trained on one public dataset (APTOS 2019); other cameras and populations are untested.', ...
        'The lesion map uses classical image processing and shows candidates for review, not confirmed lesions.', ...
        'Online results come from live web pages and must be verified by a clinician. No images or patient data are sent online.'};
    for k = 1:numel(lims)
        wl = wrapText(['-  ' lims{k}], 100);
        for j = 1:numel(wl), put(0.5, y, wl{j}, 9); y = y + 0.2; end
    end
    footer(put, H, 2, 2);
    exportPage(f, pdfPath, true);
    close(f);

    out = struct('pdf', pdfPath, ...
        'fundusPng',  fullfile(pngDir, [base '_fundus.png']), ...
        'lesionPng',  fullfile(pngDir, [base '_lesions.png']), ...
        'heatmapPng', fullfile(pngDir, [base '_heatmap.png']), 'caseId', caseId);
end

% ---------------------------------------------------------------------------
function [f, ax] = newPage(W, H, SC)
    f = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
        'Position', [0.5 0.5 W * SC H * SC], 'MenuBar', 'none', 'ToolBar', 'none', ...
        'PaperUnits', 'inches', 'PaperSize', [W * SC H * SC], 'PaperPosition', [0 0 W * SC H * SC]);
    ax = axes(f, 'Units', 'normalized', 'Position', [0 0 1 1]);
    set(ax, 'XLim', [0 W], 'YLim', [0 H], 'Visible', 'off');
    hold(ax, 'on');
end

function footer(put, H, p, n)
    put(0.5, H - 0.45, 'DR-Ishti research prototype. Not a medical device. Not for clinical diagnosis.', 7.5, 'Color', [0.45 0.45 0.45]);
    put(7.0, H - 0.45, sprintf('Page %d of %d', p, n), 7.5, 'Color', [0.45 0.45 0.45]);
end

function exportPage(f, pdfPath, doAppend)
    if exist('exportgraphics', 'file') || exist('exportgraphics') %#ok<EXIST>
        if doAppend
            exportgraphics(f, pdfPath, 'ContentType', 'image', 'Resolution', 220, 'Append', true);
        else
            if isfile(pdfPath), delete(pdfPath); end
            exportgraphics(f, pdfPath, 'ContentType', 'image', 'Resolution', 220);
        end
    else
        % Older MATLAB: one PDF per page (page 2 gets a _page2 suffix)
        if doAppend
            [d, n, e] = fileparts(pdfPath); pdfPath = fullfile(d, [n '_page2' e]);
        end
        set(f, 'PaperPositionMode', 'auto');
        print(f, pdfPath, '-dpdf', '-r220');
    end
end

function v = sget(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name)), v = s.(name); else, v = default; end
end

function s = numOrNA(x, fmt)
    if isnumeric(x) && isfinite(x), s = sprintf(fmt, x); else, s = 'n/a'; end
end

function out = wrapText(s, maxc)
    s = char(s); out = {};
    if isempty(strtrim(s)), out = {''}; return; end
    indent = regexp(s, '^\s*', 'match', 'once');
    words = strsplit(strtrim(s), ' ');
    line = indent;
    for i = 1:numel(words)
        w = words{i};
        while numel(w) > maxc - numel(indent)          % hard-break long tokens (URLs)
            if ~isempty(strtrim(line)), out{end+1} = line; line = indent; end %#ok<AGROW>
            cut = maxc - numel(indent);
            out{end+1} = [indent w(1:cut)]; %#ok<AGROW>
            w = w(cut+1:end);
        end
        if isempty(strtrim(line)), cand = [indent w]; else, cand = [line ' ' w]; end
        if numel(cand) > maxc
            if ~isempty(strtrim(line)), out{end+1} = line; end %#ok<AGROW>
            line = [indent w];
        else
            line = cand;
        end
    end
    if ~isempty(strtrim(line)), out{end+1} = line; end
end
