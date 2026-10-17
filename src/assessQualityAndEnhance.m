function [outImg, report] = assessQualityAndEnhance(imgPath)
% ASSESSQUALITYANDENHANCE  Phase 1-2 of the DR screening pipeline.
%   Loads a fundus image, runs classical quality checks (blur,
%   illumination, field-of-view), and conditionally applies CLAHE +
%   illumination normalization if quality is borderline but salvageable.
%
%   [outImg, report] = assessQualityAndEnhance(imgPath)
%
%   report is a struct with fields:
%       .isGradeable   (logical)
%       .blurScore     (double, Laplacian variance - higher = sharper)
%       .illumScore    (double, mean intensity, 0-255)
%       .fovRatio      (double, fraction of frame that is retina, not black border)
%       .enhanced      (logical, whether enhancement was applied)
%       .rejectReason  (string, empty if gradeable)

    img = imread(imgPath);
    if size(img,3) == 3
        gray = rgb2gray(img);
    else
        gray = img;
        img = cat(3, img, img, img); % normalize to RGB downstream
    end
    gray = im2double(gray);

    % --- 1. Blur check: variance of Laplacian ---
    lap = fspecial('laplacian', 0.2);
    lapResp = imfilter(gray, lap, 'replicate');
    blurScore = var(lapResp(:)) * 1e4; % scaled for readability
    BLUR_THRESHOLD = 1.5; % tune empirically on your sample set

    % --- 2. Illumination check: mean intensity + std ---
    illumMean = mean(gray(:)) * 255;
    illumStd  = std(gray(:)) * 255;
    ILLUM_LOW = 40; ILLUM_HIGH = 220;

    % --- 3. Field-of-view check: fraction of non-near-black pixels ---
    % Fundus images typically have a circular retina on a black background.
    mask = gray > 0.06; % near-black border excluded
    fovRatio = sum(mask(:)) / numel(mask);
    FOV_MIN = 0.35; % retina should occupy a reasonable chunk of the frame

    report = struct();
    report.blurScore = blurScore;
    report.illumScore = illumMean;
    report.fovRatio = fovRatio;
    report.enhanced = false;
    report.isGradeable = true;
    report.rejectReason = "";

    % --- Reject outright if severely bad ---
    if blurScore < (BLUR_THRESHOLD * 0.4)
        report.isGradeable = false;
        report.rejectReason = "Image too blurry to grade - please recapture with steady focus.";
    elseif fovRatio < (FOV_MIN * 0.5)
        report.isGradeable = false;
        report.rejectReason = "Field of view too small/off-center - recapture with retina centered.";
    end

    outImg = img;

    if ~report.isGradeable
        return;
    end

    % --- Borderline: apply enhancement ---
    needsEnhancement = (blurScore < BLUR_THRESHOLD) || ...
                        (illumMean < ILLUM_LOW) || (illumMean > ILLUM_HIGH) || ...
                        (illumStd < 15) || (fovRatio < FOV_MIN);

    if needsEnhancement
        outImg = enhanceFundusImage(img);
        report.enhanced = true;
    end
end

function outImg = enhanceFundusImage(img)
% Applies CLAHE (per-channel on L of LAB) + mild illumination normalization.
    lab = rgb2lab(img);
    L = lab(:,:,1) / 100; % normalize to 0-1 for adapthisteq
    L_eq = adapthisteq(L, 'ClipLimit', 0.01, 'Distribution', 'rayleigh');
    lab(:,:,1) = L_eq * 100;
    outImg = lab2rgb(lab);
    outImg = im2uint8(outImg);

    % Mild denoise to counter CLAHE noise amplification
    outImg = imgaussfilt(outImg, 0.5);
end
