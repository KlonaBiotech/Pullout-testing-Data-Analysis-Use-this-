function sortedLabels = sortByConcentration(labels)
%SORTBYCONCENTRATION Sort unique group/combo labels by ascending numeric
%   concentration (e.g. 5mM, 10mM, 15mM, ... 40mM) rather than MATLAB's
%   default alphabetical string sort, which gives the wrong order (e.g.
%   "10mM, 15mM, 1mM, 20mM, 25mM, 40mM, 5mM" - alphabetical, not numeric).
%
%   sortedLabels = SORTBYCONCENTRATION(labels)
%
%   labels - string/cellstr array; may be plain concentrations ("10mM")
%            or combo labels with a trailing modifier ("20mM, SuperGlue")
%            - only the leading number+mM is parsed, so combo labels
%            sort correctly by their concentration regardless of what
%            follows.
%
%   Labels with no parseable leading concentration (e.g. "Unknown") sort
%   to the end - MATLAB's sort() always places NaN last, which is what
%   parseConcentrationValue returns for those.
%
%   Used everywhere a set of groups needs a consistent, sensible display
%   order: bar chart x-axis, curve plot legends, and the stats summary
%   tables (Descriptives, Normality) all call this.

    uLabels = unique(labels, 'stable');
    concVals = zeros(numel(uLabels), 1);
    for i = 1:numel(uLabels)
        concVals(i) = parseConcentrationValue(uLabels(i));
    end
    [~, sortIdx] = sort(concVals);
    sortedLabels = uLabels(sortIdx);
end

function val = parseConcentrationValue(label)
    tokens = regexp(char(label), '^(\d+(?:\.\d+)?)\s*m[mM]', 'tokens', 'once');
    if isempty(tokens)
        val = NaN;
    else
        val = str2double(tokens{1});
    end
end
