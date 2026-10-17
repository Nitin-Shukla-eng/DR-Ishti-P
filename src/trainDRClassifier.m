function net = trainDRClassifier(imageDir, labelsCsvPath, outModelPath)
% TRAINDRCLASSIFIER  Phase 4: binary DR / No-DR classifier via transfer
%   learning on GoogLeNet. Expects the APTOS-style CSV: columns
%   "id_code" (filename stem) and "diagnosis" (0-4 ICDR grade).
%   Grade 0 -> No DR, grades 1-4 -> DR (binary collapse per your scope
%   decision).
%
%   net = trainDRClassifier('data/APTOS/raw/train_images', ...
%                            'data/APTOS/raw/train.csv', ...
%                            'models/dr_classifier_binary.mat')
%
%   Requires Deep Learning Toolbox + a pretrained GoogLeNet
%   (googlenet Add-On, install via Add-On Explorer if not present).

    arguments
        imageDir (1,1) string
        labelsCsvPath (1,1) string
        outModelPath (1,1) string = "models/dr_classifier_binary.mat"
    end

    % --- Load labels, collapse to binary ---
    T = readtable(labelsCsvPath);
    if ~ismember('id_code', T.Properties.VariableNames) || ...
       ~ismember('diagnosis', T.Properties.VariableNames)
        error('CSV must have "id_code" and "diagnosis" columns (APTOS format).');
    end
    T.label = categorical(T.diagnosis > 0, [false true], {'No_DR','DR'});

    % --- Build imageDatastore with labels ---
    filePaths = fullfile(imageDir, T.id_code + ".png");
    exists = isfile(filePaths);
    if ~all(exists)
        % try .jpg fallback
        filePathsJpg = fullfile(imageDir, T.id_code + ".jpg");
        filePaths(~exists) = filePathsJpg(~exists);
    end
    T = T(isfile(filePaths), :);
    filePaths = filePaths(isfile(filePaths));

    imds = imageDatastore(filePaths, 'Labels', T.label);

    % --- Train/validation split (80/20, stratified) ---
    [imdsTrain, imdsVal] = splitEachLabel(imds, 0.8, 'randomized');

    fprintf('Train set: %d images (%d DR, %d No_DR)\n', numel(imdsTrain.Labels), ...
        sum(imdsTrain.Labels == 'DR'), sum(imdsTrain.Labels == 'No_DR'));
    fprintf('Val set:   %d images (%d DR, %d No_DR)\n', numel(imdsVal.Labels), ...
        sum(imdsVal.Labels == 'DR'), sum(imdsVal.Labels == 'No_DR'));

    % --- Load pretrained GoogLeNet, swap final layers for binary output ---
    baseNet = googlenet;
    lgraph = layerGraph(baseNet);

    numClasses = 2;
    newFC = fullyConnectedLayer(numClasses, 'Name', 'new_fc', ...
        'WeightLearnRateFactor', 10, 'BiasLearnRateFactor', 10);
    newClassLayer = classificationLayer('Name', 'new_classoutput');

    lgraph = replaceLayer(lgraph, 'loss3-classifier', newFC);
    lgraph = replaceLayer(lgraph, 'output', newClassLayer);

    inputSize = baseNet.Layers(1).InputSize;

    % --- Augmentation: mild, fundus images shouldn't be flipped vertically
    %     in a way that breaks disc/macula orientation, but horizontal
    %     flip and small rotations are safe and help with a small dataset ---
    augmenter = imageDataAugmenter( ...
        'RandXReflection', true, ...
        'RandRotation', [-10, 10], ...
        'RandXTranslation', [-10, 10], ...
        'RandYTranslation', [-10, 10]);

    augTrain = augmentedImageDatastore(inputSize(1:2), imdsTrain, ...
        'DataAugmentation', augmenter);
    augVal = augmentedImageDatastore(inputSize(1:2), imdsVal);

    % --- Training options ---
    options = trainingOptions('adam', ...
        'MiniBatchSize', 16, ...
        'MaxEpochs', 8, ...
        'InitialLearnRate', 3e-4, ...
        'Shuffle', 'every-epoch', ...
        'ValidationData', augVal, ...
        'ValidationFrequency', 20, ...
        'Verbose', true, ...
        'Plots', 'training-progress', ...
        'ExecutionEnvironment', 'auto'); % uses GPU if available

    net = trainNetwork(augTrain, lgraph, options);

    % --- Evaluate: sensitivity / specificity on validation set ---
    predLabels = classify(net, augVal);
    trueLabels = imdsVal.Labels;

    TP = sum(predLabels == 'DR' & trueLabels == 'DR');
    FN = sum(predLabels == 'No_DR' & trueLabels == 'DR');
    TN = sum(predLabels == 'No_DR' & trueLabels == 'No_DR');
    FP = sum(predLabels == 'DR' & trueLabels == 'No_DR');

    sensitivity = TP / (TP + FN);
    specificity = TN / (TN + FP);

    fprintf('\n=== Validation Results (report these honestly to judges) ===\n');
    fprintf('Sensitivity: %.1f%%\n', sensitivity * 100);
    fprintf('Specificity: %.1f%%\n', specificity * 100);
    fprintf('Confusion:  TP=%d FN=%d TN=%d FP=%d\n', TP, FN, TN, FP);

    save(outModelPath, 'net', 'sensitivity', 'specificity');
    fprintf('Model saved to %s\n', outModelPath);
end
