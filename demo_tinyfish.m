%% DEMO_TINYFISH  Try the TinyFish features without launching the dashboard.
% Run this file. You will be asked for YOUR OWN TinyFish API key
% (https://agent.tinyfish.ai/api-keys) unless TINYFISH_API_KEY is already set.
addpath(fullfile(fileparts(mfilename('fullpath')), 'src', 'tinyfish'));

% Feature 1: human-review support (PubMed + AIOS) for an M7 conflict
lit = ishtiLiteratureCheck('GradeLowLesionHigh');
fprintf('%s\n', lit.lines{:});

% Feature 3: PM-JAY empanelled eye hospitals near the camp (district/pincode only)
hosp = ishtiFindPMJAYHospitals('Lucknow', 'Pincode', '226001', 'State', 'Uttar Pradesh');
fprintf('%s\n', hosp.lines{:});
