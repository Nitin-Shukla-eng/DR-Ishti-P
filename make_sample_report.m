%% MAKE_SAMPLE_REPORT  Headless test: pipeline -> lesion map -> PDF report.
% Run this FIRST (before the demo) to check everything works without the GUI.
% Optional: setenv('TINYFISH_API_KEY','your-key') to include online support.
projRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(projRoot, 'src'));
addpath(fullfile(projRoot, 'src', 'tinyfish'));

imgPath  = '';          % leave empty to use the first image in sample_data/
DISTRICT = 'Pune';      % camp location used for the PM-JAY lookup
STATE    = 'Maharashtra';
PINCODE  = '';

if isempty(imgPath)
    d = [dir(fullfile(projRoot, 'sample_data', '*.png')); ...
         dir(fullfile(projRoot, 'sample_data', '*.jpg')); ...
         dir(fullfile(projRoot, 'sample_data', '*.jpeg'))];
    assert(~isempty(d), 'No images found in sample_data/');
    imgPath = fullfile(d(1).folder, d(1).name);
end
fprintf('Image: %s\n', imgPath);

loaded = load(fullfile(projRoot, 'models', 'dr_classifier_binary.mat'), 'net');
result = runPipeline(imgPath, loaded.net, '');
if result.rejected, error('Image rejected: %s', result.reason); end
fprintf('Result: %s (%.1f%%), risk %s\n', result.label, result.confidence, result.riskLabel);

les = ishtiLesionAnalysis(imgPath);
[conflict, note] = ishtiConflictType(result, les);
fprintf('Lesions: %d red, %d bright, burden %s\n%s\n', les.nRed, les.nBright, les.burden, note);

extra = {};
key = tinyfishKey(false);
if ~isempty(key) && (~isempty(conflict) || ~startsWith(string(result.riskLabel), "Low"))
    if isempty(conflict), conflict = 'ReferableConfirmed'; end
    tf = ishtiTinyFishReport(conflict, DISTRICT, 'State', STATE, 'Pincode', PINCODE, 'Key', key);
    extra = tf.lines;
    fprintf('%s\n', extra{:});
elseif isempty(key)
    fprintf('No TinyFish key set: skipping online support (set TINYFISH_API_KEY to include it).\n');
end

[~, nm] = fileparts(imgPath);
out = generateScreeningPDF(imgPath, result, les, extra, ...
    fullfile(projRoot, 'reports', ['DR_Report_' nm '.pdf']));
fprintf('PDF saved: %s\n', out.pdf);
try, open(out.pdf); catch, end
