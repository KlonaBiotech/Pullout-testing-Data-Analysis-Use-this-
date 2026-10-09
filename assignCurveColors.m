function colorMap = assignCurveColors(labels)
%ASSIGNCURVECOLORS Map each unique label to a distinct solid RGB color.
%
%   colorMap = ASSIGNCURVECOLORS(labels)
%
%   labels - string/cellstr array (e.g. combined "Group, Treatment"
%            labels). Duplicates are fine; only unique values get a color.
%
%   Uses evenly-spaced hues around the color wheel (fixed saturation and
%   value, so all colors are solid/readable rather than pastel or neon)
%   rather than a fixed palette like `lines()`, which only has 7 distinct
%   colors before repeating. This guarantees N distinct colors for any N.
%
%   Note: with a very large number of groups (rule of thumb: >15-20),
%   adjacent hues become hard to visually distinguish even though they
%   are technically different colors - that's a perceptual limit, not a
%   bug in the assignment.
%
%   Returns a containers.Map from char label -> 1x3 RGB triplet.

    uLabels = unique(labels, 'stable');
    n = numel(uLabels);

    hues = linspace(0, 1, n + 1);
    hues(end) = []; % avoid duplicate color at hue=0 and hue=1 (same color)

    colorMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:n
        rgb = hsv2rgb([hues(i), 0.70, 0.85]);
        colorMap(char(uLabels(i))) = rgb;
    end
end
