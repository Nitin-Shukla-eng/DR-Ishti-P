function les = ishtiLesionAnalysis(img)
%ISHTILESIONANALYSIS  Candidate lesion map from a fundus image (classical IPT).
%   les = ishtiLesionAnalysis(imagePathOrRGB)
%
%   Finds (1) dark red-lesion candidates (microaneurysm / haemorrhage-like) and
%   (2) bright-lesion candidates (exudate-like), excluding vessels, the optic
%   disc and the image border. This is independent of the CNN and is meant to
%   help a reviewer see WHERE to look. It is NOT a diagnosis.
%
%   Output fields:
%     rgb        resized uint8 fundus image (max side 1024 px)
%     redMask, brightMask, fovMask   logical masks
%     overlay    uint8 image: cyan outlines = red candidates, yellow = bright
%     nRed, nBright, areaPct (lesion area as % of retina), burden
%                ('Low' | 'Moderate' | 'High')
%
%   Tunable thresholds are in the PARAMETERS block below. Calibrate them on a
%   few of your own sample images before the demo.

    % ------------------------- PARAMETERS ---------------------------------
    RED_K      = 3.0;    % bottom-hat threshold = mean + RED_K*std  (lower = more)
    BRIGHT_K   = 3.5;    % top-hat threshold    = mean + BRIGHT_K*std
    LOW_MAX    = 10;     % total candidates <= LOW_MAX  -> burden "Low"
    MOD_MAX    = 40;     % total candidates <= MOD_MAX  -> "Moderate", else "High"
    % -----------------------------------------------------------------------

    if ischar(img) || isstring(img), img = imread(char(img)); end
    if size(img,3) == 1, img = repmat(img, [1 1 3]); end
    img = img(:,:,1:3);
    if ~isa(img, 'uint8'), img = im2uint8(img); end
    s = 1024 / max(size(img,1), size(img,2));
    if s < 1, img = imresize(img, s); end
    rgb = im2double(img);
    [H, W, ~] = size(rgb);
    R = rgb(:,:,1);
    G = rgb(:,:,2);

    % --- retina (field of view) mask, eroded to ignore the border ring ---
    gray = rgb2gray(rgb);
    fov = imfill(bwareaopen(gray > 0.06, 2000), 'holes');
    fov = imerode(fov, strel('disk', max(3, round(0.03 * min(H, W)))));
    if nnz(fov) < 0.1 * H * W
        fov = false(H, W);
        fov(round(0.05*H):round(0.95*H), round(0.05*W):round(0.95*W)) = true;
    end

    % --- contrast-enhanced green channel ---
    Ge = adapthisteq(G, 'ClipLimit', 0.01);
    Ge = imgaussfilt(Ge, 1);

    % --- vessel mask (to keep vessels out of the red-lesion map) ---
    v = fibermetric(Ge, [2 3 4], 'ObjectPolarity', 'dark');
    v(~fov) = 0;
    vessels = bwareaopen(v > pct(v(fov), 88), 60);

    % --- red lesions: small dark blobs that are not vessels ---
    bh = imbothat(Ge, strel('disk', 9));
    bh(~fov) = 0;
    redCand = bh > mean(bh(fov)) + RED_K * std(bh(fov));
    redCand = redCand & ~imdilate(vessels, strel('disk', 2));
    redCand = bwareaopen(redCand, 5);
    cc = bwconncomp(redCand);
    redMask = false(H, W);
    if cc.NumObjects > 0
        st = regionprops(cc, 'Eccentricity', 'Solidity', 'Area');
        keep = find([st.Solidity] > 0.55 & [st.Eccentricity] < 0.97 & [st.Area] < 2500);
        redMask = ismember(labelmatrix(cc), keep);
    end

    % --- optic disc (brightest smooth red-channel region) to exclude ---
    Rs = imgaussfilt(R, 0.03 * min(H, W));
    Rs(~fov) = 0;
    [~, k] = max(Rs(:));
    [cy, cx] = ind2sub([H W], k);
    [X, Y] = meshgrid(1:W, 1:H);
    od = (X - cx).^2 + (Y - cy).^2 <= (0.10 * min(H, W))^2;

    % --- bright lesions: small bright blobs after top-hat ---
    th = imtophat(Ge, strel('disk', 15));
    th(~fov) = 0;
    brightMask = th > mean(th(fov)) + BRIGHT_K * std(th(fov));
    brightMask = bwareaopen(brightMask & ~od, 8);

    % --- counts and burden ---
    nRed    = bwconncomp(redMask).NumObjects;
    nBright = bwconncomp(brightMask).NumObjects;
    areaPct = 100 * nnz(redMask | brightMask) / max(1, nnz(fov));
    n = nRed + nBright;
    if n <= LOW_MAX
        burden = 'Low';
    elseif n <= MOD_MAX
        burden = 'Moderate';
    else
        burden = 'High';
    end

    % --- overlay: outlines so the fundus underneath stays visible ---
    ov = img;
    ov = paint(ov, bwperim(imdilate(redMask,    strel('disk', 3))), [0 255 255]);
    ov = paint(ov, bwperim(imdilate(brightMask, strel('disk', 3))), [255 255 0]);

    les = struct('rgb', img, 'redMask', redMask, 'brightMask', brightMask, ...
        'fovMask', fov, 'overlay', ov, 'nRed', nRed, 'nBright', nBright, ...
        'areaPct', areaPct, 'burden', burden);
end

function p = pct(x, q)
    x = sort(x(:));
    if isempty(x), p = 0; return; end
    p = x(max(1, min(numel(x), round(q/100 * numel(x)))));
end

function ov = paint(ov, mask, col)
    for k = 1:3
        ch = ov(:,:,k);
        ch(mask) = col(k);
        ov(:,:,k) = ch;
    end
end
