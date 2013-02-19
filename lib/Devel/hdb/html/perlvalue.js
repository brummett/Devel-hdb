// Represents a Perl value
function PerlValue(value) {
    this.value = value;
}
// We'd rather use a template for this, but Handlebars templates can't
// do different things depending on the type
// FIXME: maybe use a Handlebars helper and differnet templates for array, object, etc
PerlValue.prototype.render = function() {
    return $( renderPart(this.value) );

    function renderPart(value) {
        var html = '',
            valueType = typeof value,
            k, count, subhtml;
        if ((value === undefined) || (value === null)) {
            html += '<span class="label"><i>undef</i></span>';

        } else if (valueType == 'object') {
            html += '<span class="collapsable">';
            if (value.__blessed) {
                html += value.__blessed + '=';
            }
            html += value.__reftype + '(' + value.__refaddr.toString(16) + ') ';

            if ($.isArray(value.__value)) {
                html += 'len: ' + value.__value.length + '</span><dl>';
                for (k = 0; k < value.__value.length; k++) {
                    html += '<dt>'+ k +'</dy><dd>' + renderPart(value.__value[k]) + '</dd>';
                }
                html += '</dl>';
            }
            else if (typeof(value.__value) == 'object') {
                count = 0;
                subhtml = '';
                for (k in value.__value) {
                    count++;
                    subhtml += '<dt>' + k + '</dt><dd>' + renderPart(value.__value[k]) + '</dd>';
                }
                html += count + ' keys</span><dl>' + subhtml + '</dl>';
            }
            else {
                debugger;
                alert('unknown compound type for '+value);
            }
        } else {
            html += '<span>' + value + '</span>';
        }
        return html;
    }
};
