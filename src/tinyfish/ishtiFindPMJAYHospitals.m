function out = ishtiFindPMJAYHospitals(district, varargin)
%ISHTIFINDPMJAYHOSPITALS  TinyFish feature 3: PM-JAY empanelled eye-hospital locator.
%   A TinyFish web agent opens the public NHA PM-JAY hospital portal, searches by
%   the CAMP's district / pincode only, filters for ophthalmology / eye care and
%   returns the top 3 empanelled hospitals.
%
%   out = ishtiFindPMJAYHospitals('Lucknow', 'Pincode','226001', ...
%                                 'State','Uttar Pradesh', 'Key',k)
%   ZERO patient data is sent: only district / state / pincode of the camp.
    p = inputParser;
    addParameter(p, 'Pincode', '');
    addParameter(p, 'State', '');
    addParameter(p, 'Key', '');
    addParameter(p, 'MaxSeconds', 240);
    parse(p, varargin{:});

    key = p.Results.Key;
    if isempty(key), key = tinyfishKey(); end

    out = struct('ok', false, 'message', '', 'hospitals', struct([]), ...
        'lines', {cell(0,1)}, 'source', 'https://hem.nha.gov.in');
    if isempty(key)
        out.message = 'No TinyFish API key provided.';
        out.lines = {'Hospital lookup skipped (no TinyFish API key).'};
        return
    end

    % ---- sanitise: letters/spaces only for names, exactly 6 digits for pincode
    district = cleanName(district);
    state    = cleanName(p.Results.State);
    pin      = regexprep(char(p.Results.Pincode), '\D', '');
    if ~isempty(pin) && numel(pin) ~= 6, pin = ''; end
    if isempty(district) && isempty(pin)
        out.message = 'Provide a district or a 6-digit pincode.';
        return
    end

    where = '';
    if ~isempty(district), where = ['district "' district '"']; end
    if ~isempty(state),    where = [where ' in state "' state '"']; end
    if ~isempty(pin),      where = [where ' (pincode ' pin ')']; end

    goal = ['Use the public PM-JAY hospital search on this site (no login). ' ...
        'Search for empanelled hospitals for ' strtrim(where) '. ' ...
        'Filter by speciality Ophthalmology / Eye / Retina and only keep ACTIVE ' ...
        'empanelled hospitals. Return at most the top 3. For each give name, ' ...
        'address, district, specialties and phone if shown. ' ...
        'Do not log in, do not enter any personal information, and do not submit ' ...
        'anything other than the public hospital search form. ' ...
        'If nothing is found return an empty list.'];

    item = struct('type', 'object', 'properties', struct( ...
        'name',        struct('type', 'string'), ...
        'address',     struct('type', 'string'), ...
        'district',    struct('type', 'string'), ...
        'specialties', struct('type', 'string'), ...
        'phone',       struct('type', 'string')), ...
        'required', {{'name'}});
    schema = struct('type', 'object', 'properties', struct( ...
        'hospitals', struct('type', 'array', 'items', item)), ...
        'required', {{'hospitals'}});

    run = tfAgentRun(out.source, goal, schema, 'Key', key, ...
        'CountryCode', 'IN', 'MaxSeconds', p.Results.MaxSeconds);
    if ~run.ok
        out.message = run.message;
        out.lines = {['PM-JAY lookup unavailable: ' run.message]};
        return
    end

    h = run.result.hospitals;
    if isstruct(h), h = num2cell(h); end
    L = {'--- Nearest PM-JAY empanelled eye facilities (TinyFish) ---'};
    hs = struct('name', {}, 'address', {}, 'district', {}, 'specialties', {}, 'phone', {});
    for i = 1:min(3, numel(h))
        e = h{i};
        hs(end+1) = struct('name', gf(e,'name'), 'address', gf(e,'address'), ...
            'district', gf(e,'district'), 'specialties', gf(e,'specialties'), ...
            'phone', gf(e,'phone')); %#ok<AGROW>
        L{end+1,1} = sprintf('%d. %s', i, hs(end).name);               %#ok<AGROW>
        if ~isempty(hs(end).address), L{end+1,1} = ['   ' hs(end).address]; end %#ok<AGROW>
        if ~isempty(hs(end).phone),   L{end+1,1} = ['   Phone: ' hs(end).phone]; end %#ok<AGROW>
    end
    if isempty(hs), L{end+1,1} = 'No empanelled eye facility found for this location.'; end
    L{end+1,1} = 'Source: hem.nha.gov.in. Confirm empanelment before referring.';
    out.hospitals = hs;
    out.lines = L(:);
    out.ok = true;
end

function s = cleanName(s)
    s = regexprep(char(s), '[^A-Za-z ]', ' ');
    s = strtrim(regexprep(s, '\s+', ' '));
    s = s(1:min(end, 40));
end

function v = gf(s, f)
    if isfield(s, f) && ~isempty(s.(f)), v = char(s.(f)); else, v = ''; end
end
