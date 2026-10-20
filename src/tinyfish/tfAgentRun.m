function out = tfAgentRun(url, goal, schema, varargin)
%TFAGENTRUN  Run a TinyFish web agent synchronously (POST /v1/automation/run).
%   out = tfAgentRun(url, goal, outputSchemaStruct, 'Key',k, 'CountryCode','IN',
%                    'MaxSeconds',240, 'BrowserProfile','lite')
%   out.ok, out.message, out.result (decoded JSON), out.runId
    p = inputParser;
    addParameter(p, 'Key', '');
    addParameter(p, 'CountryCode', 'IN');
    addParameter(p, 'MaxSeconds', 240);
    addParameter(p, 'BrowserProfile', 'lite');   % 'lite' or 'stealth'
    parse(p, varargin{:});

    key = p.Results.Key;
    if isempty(key), key = tinyfishKey(); end

    out = struct('ok', false, 'message', '', 'result', [], 'runId', '');
    if isempty(key)
        out.message = 'No TinyFish API key provided.';
        return
    end

    body = struct( ...
        'url', url, ...
        'goal', goal, ...
        'output_schema', schema, ...
        'browser_profile', p.Results.BrowserProfile, ...
        'proxy_config', struct('enabled', true, 'type', 'tinyfish', ...
                               'country_code', p.Results.CountryCode), ...
        'agent_config', struct('max_duration_seconds', p.Results.MaxSeconds));

    opts = weboptions('HeaderFields', {'X-API-Key', key}, ...
        'MediaType', 'application/json', 'RequestMethod', 'post', ...
        'Timeout', p.Results.MaxSeconds + 60, 'ContentType', 'json');

    try
        resp = webwrite('https://agent.tinyfish.ai/v1/automation/run', body, opts);
    catch ME
        out.message = ['TinyFish agent request failed: ' ME.message];
        return
    end

    if isfield(resp, 'run_id') && ~isempty(resp.run_id), out.runId = char(resp.run_id); end
    if isfield(resp, 'status') && strcmp(resp.status, 'COMPLETED') && ...
            isfield(resp, 'result') && ~isempty(resp.result)
        out.ok = true;
        out.result = resp.result;
    else
        out.message = 'TinyFish run did not complete.';
        if isfield(resp, 'error') && isstruct(resp.error) && isfield(resp.error, 'message')
            out.message = char(resp.error.message);
        end
    end
end
