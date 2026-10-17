function result = explainAndReport(net, img, qualityReport, structOut, outReportPath)
% EXPLAINANDREPORT  Phase 5: runs classification, Grad-CAM, confidence
%   scoring, and produces a one-page annotated report figure that an
%   ophthalmologist can review in under 30 seconds.
%
%   result = explainAndReport(net, img, qualityReport, structOut, 'reports/patient001.png')
%
%   result struct fields: .label, .confidence, .gradcamMap

    inputSize = net.Layers(1).InputSize;
    imgResized = imresize(img, inputSize(1:2));

    % --- Classification + confidence ---
    [label, scores] = classify(net, imgResized);
    confidence = max(scores) * 100;

    % --- Grad-CAM (MATLAB built-in, Deep Learning Toolbox R2021b+) ---
    scoreMap = gradCAM(net, imgResized, label);

    result = struct();
    result.label = string(label);
    result.confidence = confidence;
    result.gradcamMap = scoreMap;

    % --- Simple risk bucket from confidence (NOT a real ICDR grade -
    %     flag this clearly as a proxy severity indicator to judges) ---
    if label == 'No_DR'
        riskLabel = "Low Risk";
    elseif confidence < 70
        riskLabel = "Medium Risk - low model confidence, recommend recapture/review";
    else
        riskLabel = "High Risk - refer for ophthalmologist review";
    end
    result.riskLabel = riskLabel;

    % --- Build annotated report figure ---
    fig = figure('Visible', 'off', 'Position', [100 100 1000 600]);

    subplot(2,3,1);
    imshow(img);
    title('Original Fundus Image');

    subplot(2,3,2);
    imshow(imgResized);
    hold on;
    imagesc(scoreMap, 'AlphaData', 0.5);
    colormap jet;
    hold off;
    title('Grad-CAM Attention');

    subplot(2,3,3);
    imshow(structOut.vesselMask);
    title(sprintf('Vessel Mask (density %.1f%%)', structOut.vesselDensity*100));

    subplot(2,3,[4 5 6]);
    axis off;
    reportText = {
        sprintf('DR Screening Report'), ...
        sprintf(' '), ...
        sprintf('Classification: %s', result.label), ...
        sprintf('Confidence: %.1f%%', result.confidence), ...
        sprintf('Risk Assessment: %s', result.riskLabel), ...
        sprintf(' '), ...
        sprintf('Image Quality: %s', ternary(qualityReport.isGradeable, 'Gradeable', 'REJECTED - ' + qualityReport.rejectReason)), ...
        sprintf('Enhancement Applied: %s', ternary(qualityReport.enhanced, 'Yes (CLAHE)', 'No')), ...
        sprintf('Optic Disc Detected: %s', ternary(~isnan(structOut.opticDiscCenter(1)), 'Yes', 'No')), ...
        sprintf(' '), ...
        sprintf('NOTE: Risk label is a confidence-based proxy, not a validated'), ...
        sprintf('ICDR 0-4 grade. For prototype/demo purposes only.')
    };
    text(0.02, 0.95, reportText, 'VerticalAlignment', 'top', 'FontSize', 11, ...
        'Interpreter', 'none');

    sgtitle('Explainable AI DR Screening - Auto-Generated Report');

    if nargin >= 5 && ~isempty(outReportPath)
        exportgraphics(fig, outReportPath, 'Resolution', 150);
    end
    close(fig);
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end
