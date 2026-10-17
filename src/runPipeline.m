function result = runPipeline(imgPath, net, outReportPath)
% RUNPIPELINE  Ties Phases 1-5 together into one call: quality check ->
%   enhancement -> structure localization -> classification -> Grad-CAM
%   -> report. This is what the app (Phase 7) calls per uploaded image.
%
%   result = runPipeline('sample.png', net, 'reports/out.png')
%
%   Load net once with: load('models/dr_classifier_binary.mat', 'net')

    [img, qualityReport] = assessQualityAndEnhance(imgPath);

    if ~qualityReport.isGradeable
        result = struct('rejected', true, 'reason', qualityReport.rejectReason, ...
            'qualityReport', qualityReport);
        fprintf('REJECTED: %s\n', qualityReport.rejectReason);
        return;
    end

    structOut = localizeStructures(img);
    explainResult = explainAndReport(net, img, qualityReport, structOut, outReportPath);

    result = struct();
    result.rejected = false;
    result.qualityReport = qualityReport;
    result.structOut = structOut;
    result.label = explainResult.label;
    result.confidence = explainResult.confidence;
    result.riskLabel = explainResult.riskLabel;
    result.gradcamMap = explainResult.gradcamMap;

    fprintf('Result: %s (%.1f%% confidence) - %s\n', result.label, ...
        result.confidence, result.riskLabel);
end
