function metrics = evaluateDRClassifier(imageFolder, testCsvPath, modelPath)
% evaluateDRClassifier  Evaluate the trained binary DR classifier on
% test_images/ using labels from test.csv.
%
% USAGE:
%   metrics = evaluateDRClassifier('data/APTOS/raw/test_images', ...
%                                   'data/APTOS/raw/test.csv', ...
%                                   'models/dr_classifier_binary.mat');
%
% REQUIRES testCsvPath to have columns id_code AND diagnosis. If your
% test.csv only has id_code (standard Kaggle competition test.csv has no
% ground-truth labels), this script will stop with a clear error instead
% of silently producing meaningless numbers.
%
% Images are looked up as fullfile(imageFolder, id_code + '.png').
%
% OUTPUT:
%   metrics - struct with Sensitivity, Specificity, Accuracy, AUC,
%             ConfusionMat, and per-image predictions/scores.

    if nargin < 1, imageFolder = 'data/APTOS/raw/test_images'; end
    if nargin < 2, testCsvPath = 'data/APTOS/raw/test.csv'; end
    if nargin < 3, modelPath   = 'models/dr_classifier_binary.mat'; end

    %% 1. Load trained network
    fprintf('Loading model from %s ...\n', modelPath);
    S = load(modelPath, 'net');
    net = S.net;

    inputSize = net.Layers(1).InputSize(1:2);
    classNames = net.Layers(end).Classes;
    fprintf('Model input size: %dx%d, classes: %s\n', ...
        inputSize(1), inputSize(2), strjoin(string(classNames), ', '));

    %% 2. Load test.csv and verify it actually has ground-truth labels
    T = readtable(testCsvPath);
    fprintf('%s columns: %s\n', testCsvPath, strjoin(T.Properties.VariableNames, ', '));

    if ~ismember('id_code', T.Properties.VariableNames)
        error(['Expected an id_code column in %s but did not find one. ' ...
               'Found: %s'], testCsvPath, strjoin(T.Properties.VariableNames, ', '));
    end
    if ~ismember('diagnosis', T.Properties.VariableNames)
        error(['%s has no "diagnosis" column -- it has no ground-truth labels, ' ...
               'so it cannot be used to compute sensitivity/specificity/accuracy. ' ...
               '(This is normal for the standard Kaggle APTOS competition test.csv -- ' ...
               'it is meant for submission, not evaluation.) ' ...
               'Use a labeled held-out split from train.csv instead (see splitDRDataset.m).'], ...
               testCsvPath);
    end

    %% 3. Build file list + ground-truth labels
    nRows = height(T);
    files = strings(nRows, 1);
    for i = 1:nRows
        idc = string(T.id_code(i));
        candidate = fullfile(imageFolder, idc + ".png");
        if ~isfile(candidate)
            candidate = fullfile(imageFolder, idc);  % in case id_code already has extension
        end
        files(i) = candidate;
    end

    missing = ~isfile(files);
    if any(missing)
        warning('%d images listed in %s were not found in %s and will be skipped.', ...
            sum(missing), testCsvPath, imageFolder);
        files(missing) = [];
        T(missing, :) = [];
    end
    if isempty(files)
        error('No test images found. Check imageFolder and testCsvPath paths.');
    end

    % Ground truth: 0 = No_DR, >0 = DR (same binarization used in training)
    isDRTrue = T.diagnosis > 0;
    trueLabelStr = repmat("No_DR", numel(isDRTrue), 1);
    trueLabelStr(isDRTrue) = "DR";

    % Match against actual class names the network uses
    classNameStrs = string(classNames);
    posIdx = find(contains(lower(classNameStrs), "dr") & ~contains(lower(classNameStrs), "no"));
    if isempty(posIdx)
        warning('Could not auto-detect the positive (DR) class name from net.Layers(end).Classes -- defaulting to class 2. Check classNames printed above and fix "posIdx" manually if wrong.');
        posIdx = 2;
    end
    posClassName = classNameStrs(posIdx);
    negIdx = setdiff(1:numel(classNameStrs), posIdx);
    negClassName = classNameStrs(negIdx);

    trueLabelStr(trueLabelStr == "DR") = posClassName;
    trueLabelStr(trueLabelStr == "No_DR") = negClassName;
    trueLabels = categorical(trueLabelStr, classNameStrs);

    fprintf('Loaded %d test images (%d DR, %d No_DR)\n', ...
        numel(files), sum(isDRTrue), sum(~isDRTrue));

    %% 4. Build datastore and run inference
    imds = imageDatastore(files);
    augTest = augmentedImageDatastore(inputSize, imds, 'ColorPreprocessing', 'gray2rgb');

    fprintf('Running inference on test set...\n');
    [predLabels, scores] = classify(net, augTest);

    %% 5. Confusion matrix + core metrics
    confMat = confusionmat(trueLabels, predLabels, 'Order', classNames);
    posClassIdx = find(classNames == posClassName);
    negClassIdx = find(classNames == negClassName);

    TP = confMat(posClassIdx, posClassIdx);
    FN = sum(confMat(posClassIdx, :)) - TP;
    TN = confMat(negClassIdx, negClassIdx);
    FP = sum(confMat(negClassIdx, :)) - TN;

    sensitivity = TP / (TP + FN) * 100;
    specificity = TN / (TN + FP) * 100;
    accuracy    = sum(diag(confMat)) / sum(confMat(:)) * 100;

    %% 6. ROC / AUC
    posScoreCol = scores(:, posClassIdx);
    trueBinary = double(trueLabels == posClassName);
    [rocX, rocY, ~, AUC] = perfcurve(trueBinary, posScoreCol, 1);

    %% 7. Print report
    fprintf('\n========== TEST SET RESULTS (n=%d) ==========\n', numel(trueLabels));
    fprintf('Sensitivity (Recall for %s): %.1f%%\n', posClassName, sensitivity);
    fprintf('Specificity: %.1f%%\n', specificity);
    fprintf('Accuracy: %.1f%%\n', accuracy);
    fprintf('AUC: %.3f\n', AUC);
    fprintf('Confusion:  TP=%d FN=%d TN=%d FP=%d\n', TP, FN, TN, FP);
    fprintf('===============================================\n\n');
    fprintf('NOTE: These are your real held-out numbers -- report THESE to judges,\n');
    fprintf('not training accuracy, and not the 90%%/85%% target from the problem statement.\n\n');

    %% 8. Plots
    figure('Name', 'DR Classifier Evaluation', 'Position', [100 100 900 400]);

    subplot(1,2,1);
    confusionchart(trueLabels, predLabels);
    title('Confusion Matrix (Test Set)');

    subplot(1,2,2);
    plot(rocX, rocY, 'LineWidth', 2); hold on;
    plot([0 1], [0 1], 'k--');
    xlabel('False Positive Rate'); ylabel('True Positive Rate');
    title(sprintf('ROC Curve (AUC = %.3f)', AUC));
    grid on;

    %% 9. Return everything
    metrics.Sensitivity  = sensitivity;
    metrics.Specificity  = specificity;
    metrics.Accuracy     = accuracy;
    metrics.AUC          = AUC;
    metrics.ConfusionMat = confMat;
    metrics.TP = TP; metrics.FN = FN; metrics.TN = TN; metrics.FP = FP;
    metrics.TrueLabels = trueLabels;
    metrics.PredLabels = predLabels;
    metrics.Scores     = scores;
    metrics.Files      = files;

    misIdx = find(trueLabels ~= predLabels);
    if ~isempty(misIdx)
        fprintf('%d misclassified images (first 10 shown):\n', numel(misIdx));
        for i = 1:min(10, numel(misIdx))
            k = misIdx(i);
            fprintf('  %s | true=%s pred=%s (score=%.2f)\n', ...
                files(k), string(trueLabels(k)), string(predLabels(k)), scores(k, posClassIdx));
        end
    end
end
