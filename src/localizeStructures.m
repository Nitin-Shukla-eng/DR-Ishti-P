function structOut = localizeStructures(img)
% LOCALIZESTRUCTURES  Phase 3: classical (non-DL) structure localization.
%   Fast, explainable stand-ins for full segmentation — optic disc
%   center via brightest large blob, and a basic vessel mask via
%   matched filtering. Good enough for a one-day demo; state clearly
%   to judges these are classical CV proxies, not trained segmentation
%   networks.
%
%   structOut.opticDiscCenter  [x, y]
%   structOut.opticDiscRadius  scalar (approx, pixels)
%   structOut.vesselMask       logical mask, same size as image
%   structOut.vesselDensity    scalar, fraction of pixels flagged as vessel

    if size(img,3) == 3
        gray = rgb2gray(img);
        green = img(:,:,2); % green channel has best vessel contrast
    else
        gray = img;
        green = img;
    end
    gray = im2double(gray);
    green = im2double(green);

    % --- Optic disc: brightest, largest connected bright region ---
    brightThresh = prctile(gray(:), 97);
    brightMask = gray >= brightThresh;
    brightMask = imopen(brightMask, strel('disk', 5));
    brightMask = bwareafilt(brightMask, 1); % keep only the largest blob

    structOut = struct();
    if any(brightMask(:))
        props = regionprops(brightMask, 'Centroid', 'EquivDiameter');
        structOut.opticDiscCenter = props(1).Centroid;
        structOut.opticDiscRadius = props(1).EquivDiameter / 2;
    else
        structOut.opticDiscCenter = [NaN, NaN];
        structOut.opticDiscRadius = NaN;
    end

    % --- Vessel mask: CLAHE on green channel + matched filter approx ---
    greenEq = adapthisteq(green, 'ClipLimit', 0.008);
    % Approximate vessel enhancement via multiscale top-hat (classical,
    % fast substitute for a full Frangi/matched-filter bank)
    se1 = strel('disk', 2);
    se2 = strel('disk', 6);
    topHat = imtophat(imcomplement(greenEq), se1) + imtophat(imcomplement(greenEq), se2);
    vesselMask = topHat > graythresh(topHat) * max(topHat(:)) * 0.55;
    vesselMask = bwareaopen(vesselMask, 20); % remove small noise specks

    structOut.vesselMask = vesselMask;
    structOut.vesselDensity = sum(vesselMask(:)) / numel(vesselMask);
end
