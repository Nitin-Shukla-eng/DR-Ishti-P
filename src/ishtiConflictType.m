function [conflict, note] = ishtiConflictType(result, les)
%ISHTICONFLICTTYPE  Compare the CNN result with the lesion evidence.
%   [conflict, note] = ishtiConflictType(result, les)
%   conflict : generic, PHI-free topic for the TinyFish human-review lookup
%              ('' when the result is low risk and consistent)
%   note     : one sentence for the screen / PDF report
    lbl  = lower(string(result.label));
    isDR = (contains(lbl, "dr") || contains(lbl, "retinopathy")) && ~contains(lbl, "no");
    riskLow = startsWith(string(result.riskLabel), "Low");
    b = 'Unknown';
    if ~isempty(les) && isfield(les, 'burden'), b = les.burden; end

    conflict = '';
    note = 'Classifier output and lesion evidence are consistent.';

    if isDR && strcmp(b, 'Low')
        conflict = 'classifier predicts DR but few lesions detected';
        note = 'DISCORDANCE: classifier flags DR but few lesion candidates were found. Reviewer should check the heatmap.';
    elseif ~isDR && strcmp(b, 'High')
        conflict = 'GradeZeroLesionPresent';
        note = 'DISCORDANCE: classifier says No DR but many lesion candidates were found. Reviewer should check the lesion map.';
    elseif isDR
        conflict = 'ReferableConfirmed';
        note = sprintf('Classifier flags DR and lesion candidates support it (burden: %s). Referral pathway suggested.', b);
    elseif ~riskLow
        conflict = 'GradeZeroLesionPresent';
        note = 'No DR predicted, but confidence is borderline. A second look is advised.';
    end
end
