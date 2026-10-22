function out = ishtiHeatOverlay(rgb, cam, alpha)
%ISHTIHEATOVERLAY  Blend a Grad-CAM map (jet colours) onto a fundus image.
%   out = ishtiHeatOverlay(rgbUint8, gradcamMap, 0.5)  ->  uint8 RGB image.
%   Low-attention areas stay transparent so the fundus remains readable.
    if nargin < 3, alpha = 0.5; end
    rgb = im2double(rgb);
    cam = double(cam);
    if ndims(cam) == 3, cam = mean(cam, 3); end
    cam(~isfinite(cam)) = 0;
    cam = imresize(cam, [size(rgb,1) size(rgb,2)]);
    cam = cam - min(cam(:));
    m = max(cam(:));
    if m > 0, cam = cam / m; end
    cmap = jet(256);
    idx  = round(cam * 255) + 1;
    heat = reshape(cmap(idx(:), :), [size(cam), 3]);
    w = alpha * min(1, cam * 1.5);          % weight by attention strength
    w3 = repmat(w, [1 1 3]);
    out = im2uint8((1 - w3) .* rgb + w3 .* heat);
end
