function info = getReferralInfo(locationText, maxResults)
% GETREFERRALINFO  Optional add-on: looks up eye-care referral resources
%   with the TinyFish Search API and returns the top results.
%
%   info = getReferralInfo('Pune')
%   info = getReferralInfo('Pune', 3)
%
%   Setup (once per MATLAB session, never commit your key):
%       setenv('TINYFISH_API_KEY', 'your-key-here')
%   Get a free key at https://agent.tinyfish.ai/api-keys
%
%   PRIVACY: only a generic text query (condition + city) is sent.
%   No images, patient details or screening results leave MATLAB.
%
%   info fields:
%       .ok       true if results were retrieved
%       .message  status text (shown in the app if lookup is unavailable)
%       .items    struct array with .title, .url, .snippet

    if nargin < 1 || strlength(string(locationText)) == 0
        locationText = "India";
    end
    if nargin < 2
        maxResults = 3;
    end

    info = struct('ok', false, 'message', "", ...
        'items', struct('title', {}, 'url', {}, 'snippet', {}));

    apiKey = getenv('TINYFISH_API_KEY');
    if isempty(apiKey)
        info.message = "Referral lookup is off (set TINYFISH_API_KEY to enable).";
        return;
    end

    query = sprintf('diabetic retinopathy retina specialist eye hospital %s', ...
        char(string(locationText)));

    try
        opts = weboptions('HeaderFields', {'X-API-Key', apiKey}, ...
            'Timeout', 20, 'ContentType', 'json');
        res = webread('https://api.search.tinyfish.ai', 'query', query, opts);

        if ~isstruct(res) || ~isfield(res, 'results') || isempty(res.results)
            info.message = "No referral results found.";
            return;
        end

        raw = res.results;
        if isstruct(raw)
            raw = num2cell(raw);   % homogeneous results decode as a struct array
        end

        n = min(numel(raw), maxResults);
        for k = 1:n
            r = raw{k};
            info.items(end+1) = struct( ...
                'title',   safeField(r, 'title'), ...
                'url',     safeField(r, 'url'), ...
                'snippet', safeField(r, 'snippet'));
        end
        info.ok = true;
        info.message = "Referral resources found via TinyFish Search.";
    catch ME
        info.message = "Referral lookup unavailable: " + string(ME.message);
    end
end

function out = safeField(s, name)
    if isfield(s, name) && ~isempty(s.(name))
        out = string(s.(name));
    else
        out = "";
    end
end
