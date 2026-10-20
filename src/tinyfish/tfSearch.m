function out = tfSearch(query, varargin)
%TFSEARCH  Thin wrapper around the TinyFish Search API (GET api.search.tinyfish.ai).
%   out = tfSearch(query, 'Key',k, 'Purpose',txt, 'MaxResults',5)
%   out.ok, out.message, out.results (struct array: title, snippet, url, site)
    p = inputParser;
    addParameter(p, 'Key', '');
    addParameter(p, 'Purpose', '');
    addParameter(p, 'MaxResults', 5);
    parse(p, varargin{:});

    key = p.Results.Key;
    if isempty(key), key = tinyfishKey(); end

    out = struct('ok', false, 'message', '', ...
        'results', struct('title', {}, 'snippet', {}, 'url', {}, 'site', {}));
    if isempty(key)
        out.message = 'No TinyFish API key provided.';
        return
    end

    opts = weboptions('HeaderFields', {'X-API-Key', key}, ...
        'Timeout', 60, 'ContentType', 'json');
    args = {'query', query};
    if ~isempty(p.Results.Purpose)
        args = [args, {'purpose', p.Results.Purpose}];
    end

    try
        resp = webread('https://api.search.tinyfish.ai', args{:}, opts);
    catch ME
        out.message = ['TinyFish search failed: ' ME.message];
        return
    end

    r = resp.results;
    if isstruct(r), r = num2cell(r); end
    n = min(numel(r), p.Results.MaxResults);
    for i = 1:n
        e = r{i};
        out.results(end+1) = struct( ...
            'title',   getf(e, 'title'), ...
            'snippet', getf(e, 'snippet'), ...
            'url',     getf(e, 'url'), ...
            'site',    getf(e, 'site_name')); %#ok<AGROW>
    end
    out.ok = true;
end

function v = getf(s, f)
    if isfield(s, f) && ~isempty(s.(f)), v = char(s.(f)); else, v = ''; end
end
