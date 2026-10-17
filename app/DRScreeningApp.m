function DRScreeningApp()
% DRSCREENINGAPP  Phase 7: programmatic MATLAB app for the judge demo.
%   Built with uifigure (not App Designer .mlapp) so it's plain
%   version-controllable code. Run: DRScreeningApp()
%
%   Requires models/dr_classifier_binary.mat (trained in Phase 4) to
%   exist and be on the MATLAB path, or update MODEL_PATH below.

    MODEL_PATH = fullfile('models', 'dr_classifier_binary.mat');

    fig = uifigure('Name', 'Explainable AI - DR Screening Prototype', ...
        'Position', [100 100 950 650]);

    uilabel(fig, 'Text', 'Explainable AI for Diabetic Retinopathy Screening', ...
        'FontSize', 18, 'FontWeight', 'bold', 'Position', [30 600 700 30]);

    axImg = uiaxes(fig, 'Position', [30 250 350 330]);
    title(axImg, 'Uploaded Fundus Image');

    axCam = uiaxes(fig, 'Position', [400 250 350 330]);
    title(axCam, 'Grad-CAM Attention');

    resultArea = uitextarea(fig, 'Position', [30 30 720 200], ...
        'Editable', 'off', 'FontSize', 13, ...
        'Value', {'Upload a fundus image to begin screening.'});

    uploadBtn = uibutton(fig, 'Text', 'Upload Fundus Image', ...
        'Position', [770 560 150 40], 'FontSize', 13);

    netHolder = struct('net', []); % simple closure-captured state

    uploadBtn.ButtonPushedFcn = @(btn, event) onUpload();

    function onUpload()
        [file, path] = uigetfile({'*.png;*.jpg;*.jpeg', 'Fundus Images'});
        if isequal(file, 0)
            return;
        end
        imgPath = fullfile(path, file);

        if isempty(netHolder.net)
            if ~isfile(MODEL_PATH)
                uialert(fig, sprintf('Model not found at %s. Run trainDRClassifier first.', ...
                    MODEL_PATH), 'Model Missing');
                return;
            end
            loaded = load(MODEL_PATH, 'net');
            netHolder.net = loaded.net;
        end

        resultArea.Value = {'Running pipeline...'};
        drawnow;

        img = imread(imgPath);
        imshow(img, 'Parent', axImg);

        result = runPipeline(imgPath, netHolder.net, '');

        if result.rejected
            resultArea.Value = {'IMAGE REJECTED', '', result.reason};
            cla(axCam);
            return;
        end

        imagesc(axCam, result.gradcamMap);
        colormap(axCam, 'jet');
        axis(axCam, 'off');

        lines = {
            sprintf('Classification: %s', result.label), ...
            sprintf('Confidence: %.1f%%', result.confidence), ...
            sprintf('Risk: %s', result.riskLabel), ...
            '', ...
            sprintf('Image Quality: Gradeable (enhancement applied: %s)', ...
                mat2str(result.qualityReport.enhanced)), ...
            sprintf('Vessel density: %.2f%%', result.structOut.vesselDensity*100), ...
            '', ...
            'NOTE: Prototype demo. Risk label is a confidence-based proxy,', ...
            'not a clinically validated ICDR 0-4 grade.'
        };
        resultArea.Value = lines;
    end
end
