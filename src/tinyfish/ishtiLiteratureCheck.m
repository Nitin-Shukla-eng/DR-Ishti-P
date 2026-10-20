function out = ishtiLiteratureCheck(conflictType, varargin)
%ISHTILITERATURECHECK  TinyFish feature 1: Human-Review support.
%   When the M7 trust layer flags a clinical discordance (e.g. grade vs lesion
%   mismatch), look up PubMed and AIOS guidance for THAT discordance.
%
%   conflictType (use one of these; no patient data is ever sent):
%     'GradeLowLesionHigh'     e.g. Grade 1 predicted but severe haemorrhages seen
%     'GradeZeroLesionPresent' e.g. Grade 0 predicted but significant lesion area
%     'ReferableConfirmed'     referable DR confirmed (ICDR grade 2 to 4)
%   or a short generic clinical phrase (sanitised, max 150 chars).
%
%   out = ishtiLiteratureCheck('GradeLowLesionHigh', 'Key', k, 'MaxResults', 3)
%   out.lines is a cellstr ready to append to the screening report.
    p = inputParser;
    addParameter(p, 'Key', '');
    addParameter(p, 'MaxResults', 3);
    parse(p, varargin{:});

    key = p.Results.Key;
    if isempty(key), key = tinyfishKey(); end

    terms = conflictTerms(conflictType);
    out = struct('ok', false, 'query', terms, 'pubmed', [], 'aios', [], ...
        'lines', {cell(0,1)}, 'message', '');
    if isempty(key)
        out.message = 'No TinyFish API key provided.';
        out.lines = {'Literature check skipped (no TinyFish API key).'};
        return
    end

    purpose = ['Find peer-reviewed or guideline evidence a clinician can use to ' ...
               'resolve a diabetic retinopathy grading discordance.'];

    pm = tfSearch(['site:pubmed.ncbi.nlm.nih.gov ' terms], 'Key', key, ...
        'Purpose', purpose, 'MaxResults', p.Results.MaxResults);
    ai = tfSearch(['site:aios.org diabetic retinopathy guidelines ' terms], 'Key', key, ...
        'Purpose', purpose, 'MaxResults', p.Results.MaxResults);
    if ai.ok && isempty(ai.results)   % fallback if the site filter returns nothing
        ai = tfSearch(['AIOS India diabetic retinopathy guidelines ' terms], 'Key', key, ...
            'Purpose', purpose, 'MaxResults', p.Results.MaxResults);
    end

    out.pubmed = pm.results;
    out.aios   = ai.results;
    out.ok     = pm.ok || ai.ok;
    out.message = strtrim([pm.message ' ' ai.message]);

    L = {'--- Doctor alert: clinical discordance, evidence lookup (TinyFish) ---'; ...
         ['Topic searched: ' terms]};
    L = [L; fmt('PubMed', pm.results)];
    L = [L; fmt('AIOS',   ai.results)];
    if ~out.ok, L = [L; {['Lookup unavailable: ' out.message]}]; end
    L = [L; {'Verify all sources clinically. Not a diagnosis.'}];
    out.lines = L;
end

function terms = conflictTerms(c)
    switch char(c)
        case 'GradeLowLesionHigh'
            terms = 'diabetic retinopathy mild grade with severe hemorrhages grading lesion discordance';
        case 'GradeZeroLesionPresent'
            terms = 'diabetic retinopathy no DR grade with microaneurysms hemorrhages lesions missed';
        case 'ReferableConfirmed'
            terms = 'referable diabetic retinopathy moderate severe proliferative referral guideline';
        otherwise
            s = regexprep(lower(char(c)), '[^a-z0-9 \-]', ' ');
            s = strtrim(regexprep(s, '\s+', ' '));
            terms = ['diabetic retinopathy ' s(1:min(end, 150))];
    end
end

function L = fmt(tag, results)
    L = cell(0,1);
    for i = 1:numel(results)
        sn = regexprep(results(i).snippet, '\s+', ' ');
        sn = sn(1:min(end, 160));
        L{end+1,1} = sprintf('[%s %d] %s', tag, i, results(i).title);  %#ok<AGROW>
        if ~isempty(sn), L{end+1,1} = ['    ' sn]; end                  %#ok<AGROW>
        L{end+1,1} = ['    ' results(i).url];                          %#ok<AGROW>
    end
end
