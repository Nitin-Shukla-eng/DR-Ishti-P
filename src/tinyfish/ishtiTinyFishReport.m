function out = ishtiTinyFishReport(conflictType, district, varargin)
%ISHTITINYFISHREPORT  Combines TinyFish features 1 + 3 into report lines.
%   tf = ishtiTinyFishReport('GradeLowLesionHigh', 'Lucknow', ...
%            'Pincode','226001', 'State','Uttar Pradesh');
%   reportLines = [reportLines; tf.lines];     % append to your existing report
%
%   Options: 'Key', 'SkipLiterature', 'SkipHospitals'
%   Needs the visitor's own TinyFish key (env var or dialog, see tinyfishKey.m).
%   Everything is optional: if no key is given the app runs exactly as before.
    p = inputParser;
    addParameter(p, 'Pincode', '');
    addParameter(p, 'State', '');
    addParameter(p, 'Key', '');
    addParameter(p, 'SkipLiterature', false);
    addParameter(p, 'SkipHospitals', false);
    parse(p, varargin{:});

    key = p.Results.Key;
    if isempty(key), key = tinyfishKey(); end

    out = struct('ok', false, 'lines', {cell(0,1)}, 'literature', [], 'hospitals', []);
    if isempty(key)
        out.lines = {'TinyFish online lookups skipped (no API key supplied).'};
        return
    end

    L = cell(0,1);
    if ~p.Results.SkipLiterature && ~isempty(conflictType)
        out.literature = ishtiLiteratureCheck(conflictType, 'Key', key);
        L = [L; out.literature.lines(:)];
    end
    if ~p.Results.SkipHospitals
        out.hospitals = ishtiFindPMJAYHospitals(district, 'Key', key, ...
            'Pincode', p.Results.Pincode, 'State', p.Results.State);
        L = [L; out.hospitals.lines(:)];
    end
    out.lines = L;
    out.ok = true;
end
