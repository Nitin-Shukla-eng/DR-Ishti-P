function key = tinyfishKey(interactive)
%TINYFISHKEY  Return the visitor's OWN TinyFish API key (bring-your-own-key).
%   The key is read from the TINYFISH_API_KEY environment variable. If it is
%   not set and MATLAB has a desktop, a dialog asks the visitor to paste one.
%   The key is kept for the current MATLAB session only and is never written
%   to any file in this repository.
%
%   Get a free key at https://agent.tinyfish.ai/api-keys
    if nargin < 1, interactive = true; end
    key = strtrim(getenv('TINYFISH_API_KEY'));
    if isempty(key) && interactive && usejava('desktop')
        answer = inputdlg({['Paste your own TinyFish API key ' ...
            '(agent.tinyfish.ai/api-keys). It is used for this MATLAB ' ...
            'session only and is never saved.']}, 'TinyFish API key', [1 70]);
        if ~isempty(answer)
            key = strtrim(answer{1});
            if ~isempty(key), setenv('TINYFISH_API_KEY', key); end
        end
    end
end
