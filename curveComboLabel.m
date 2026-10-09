function label = curveComboLabel(groupVal, treatmentVal)
%CURVECOMBOLABEL Build the display/color-key label for a Group+Treatment
%   combination, e.g. "10mM, PT" or just "10mM" if there's no meaningful
%   treatment value. Used everywhere a curve or bar needs a consistent
%   combo label - the embedded UI plots, pop-out figures, and PPTX
%   report all call this same function, so colors and legend text never
%   drift out of sync with each other.
%
%   Accepts either two separate string/char arguments, or a struct/table
%   row with Group and Treatment fields (call as
%   CURVECOMBOLABEL(entry.Group, entry.Treatment) either way).

    if nargin < 2 || isempty(treatmentVal) || strcmpi(string(treatmentVal), 'none')
        label = string(groupVal);
    else
        label = string(sprintf('%s, %s', groupVal, treatmentVal));
    end
end
