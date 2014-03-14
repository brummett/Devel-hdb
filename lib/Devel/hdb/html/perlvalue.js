// Represents a Perl value
function PerlValue() { }
PerlValue.prototype.render = function(view) {
    return this.renderHeader(view) + this.renderValue(view);
}

PerlValue.prototype.escapedValue = function(v) {
    if (v === undefined) {
        v = this.value;
    }
    return Handlebars.Utils.escapeExpression(v);
}

PerlValue.parseFromEval = function(value) {
    var pv;
    try {
        if (value && value.__tied) {
            pv = new PerlValue.tied(value);
        } else if (value && value.__recursive) {
            pv = new PerlValue.recursive(value);
        // null _is_ an object, but we want to represent it as a scalar/undef
        } else if ((typeof value === 'object') && (value !== undefined) && (value !== null)) {
            pv = new PerlValue[ value.__reftype](value);
        } else {
            pv = new PerlValue.scalar(value);
        }
    } catch(err) {
        console.log('Exception when parsing data for popover variable at ' +err.stack);
        console.log('data was '+value);
        console.log('Exception was '+err);
    }

    return pv;
}
//PerlValue.prototype.render = function() {
//    return this.value.renderHeader() + this.value.renderValue();
//}


PerlValue.exception = function(value) {
    this.value = value;
    this.type = 'exception';
};
PerlValue.exception.prototype = new PerlValue();
PerlValue.exception.prototype.renderValue = function(view) {
    return '<span class="label label-important PerlValue">'+this.escapedValue()+'</span>';
};

// simple scalar values
PerlValue.scalar = function(value) {
    this.value = value;
    this.type = 'scalar';
}
PerlValue.scalar.prototype = new PerlValue();
PerlValue.scalar.prototype.renderValue = function(view) {
    if ((this.value === undefined) || (this.value === null)) {
        return '<span class="label PerlValue"><i>undef</i></span>';
    } else {
        return '<span class="PerlValue">'
                + this.escapedValue() + '</span>';
    }
}

// SCALAR ref values
PerlValue.SCALAR = function(value) {
    this.value = PerlValue.parseFromEval(value.__value);
    this.type = value.__reftype;
    this.refaddr = value.__refaddr;
    this.blessed = value.__blessed;
}
PerlValue.SCALAR.prototype = new PerlValue();
PerlValue.SCALAR.prototype.renderHeader = function(view) {
    return '<span>' + this.refHeaderString() + '</span>';
};
PerlValue.SCALAR.prototype.renderValue = function(view) {
    return '<span class="PerlValue">' + this.value.render(view) + '</span>';
}

// ARRAY ref values
PerlValue.ARRAY = function(value) {
    this.type = value.__reftype;
    this.refaddr = value.__refaddr;
    this.blessed = value.__blessed;
    this.count = value.__value.length;
    this.value = [];
    var i;
    for (var i = 0; i < this.count; i++) {
        this.value[i] = PerlValue.parseFromEval(value.__value[i]);
    }
}
PerlValue.ARRAY.prototype = new PerlValue();
PerlValue.ARRAY.prototype.renderHeader = function(view) {
    return '<span>' + this.refHeaderString() + '</span>'
            + ' <span class="badge badge-info'
            + (view === 'condensed' ? '' : ' expr-collapse-button')
            + '">' + this.count +'</span>';
}
PerlValue.ARRAY.prototype.renderValue = function(view) {
    if (view === 'condensed') {
        return '';
    }

    var html = '<dl class="PerlValue">';
    for(var i = 0; i < this.value.length; i++) {
        html += '<dt>' + i + '</dt><dd>'
                + this.value[i].render(view) + '</dd>';
    }
    return html + '</dl>';
}


// HASH ref values
PerlValue.HASH = function(value) {
    this.type = value.__reftype;
    this.refaddr = value.__refaddr;
    this.blessed = value.__blessed;
    this.count = 0;
    this.value = {};
    var k;
    for (k in value.__value) {
        if (value.__value.hasOwnProperty(k)) {
            this.count++;
            this.value[k] = PerlValue.parseFromEval(value.__value[k]);
        }
    }
}
PerlValue.HASH.prototype = new PerlValue();
PerlValue.HASH.prototype.renderHeader = function(view) {
    return '<span>' + this.refHeaderString() + '</span>'
            + ' <span class="badge badge-info'
            + (view === 'condensed' ? '' : ' expr-collapse-button')
            + '">' + this.count + '</span>';
}
PerlValue.HASH.prototype.renderValue = function(view) {
    if (view === 'condensed') {
        return '';
    }

    var html = '<dl class="PerlValue">',
        k;
    for (key in this.value) {
        html += '<dt>' + this.escapedValue(key) + '</dt><dd>' + this.value[key].render(view) + '</dd>';
    }
    return html + '</dl>';
}


// GLOB ref values
PerlValue.GLOB = function(value) {
    this.type = value.__reftype;
    this.refaddr = value.__refaddr;
    this.blessed = value.__blessed;
    this.value = {};
    var k;
    for (k in value.__value) {
        if (k === 'PACKAGE') {
            this.pkg = value.__value[k];
        } else if (k === 'NAME') {
            this.name = value.__value[k];
        } else if (k === 'IOseek') {
            this.ioseek = value.__value[k];
        } else if (value.__value.hasOwnProperty(k)) {
            this.value[k] = PerlValue.parseFromEval(value.__value[k]);
        }
    }
}
PerlValue.GLOB.prototype = new PerlValue();
PerlValue.GLOB.prototype.renderHeader = function(view) {
    return '<span>' + this.refHeaderString() + '</span>'
            + ' <span class="badge badge-info'
            + (view === 'condensed' ? '">' : ' expr-collapse-button">&plusmn;')
            + '</span>';
}
PerlValue.GLOB.prototype.renderValue = function(view) {
    if (view === 'condensed') {
        return '';
    }

    var html = '<dl class="PerlValue">',
        k;
    html += '<dt><span class="label">Name</span></dt><dd><span><b>' + this.pkg + '</b>::' + this.name + '</span></dd>';
    for (k in this.value) {
        var rendered = this.value[k].render(view);
        html += '<dt><span class="label label-success">' + k + '</span></dt><dd>'
                + ( k === 'IO' ? rendered + ' @ ' + this.ioseek : rendered )
                + '</dd>';
    }
    return html + '</dl>';
}

// CODE ref values
PerlValue.CODE = function(value) {
    this.value = value.__value;
    this.refaddr = value.__refaddr;
    this.type = value.__reftype;
    this.blessed = value.__blessed;
}
PerlValue.CODE.prototype = new PerlValue();
PerlValue.CODE.prototype.render = function(view) {
    return '<span>' + this.refHeaderString() + '</span>';
}

// REF ref values
PerlValue.REF = function(value) {
    this.value = PerlValue.parseFromEval(value.__value);
    this.refaddr = value.__refaddr;
    this.type = value.__reftype;
    this.blessed = value.__blessed;
}
PerlValue.REF.prototype = new PerlValue();
PerlValue.REF.prototype.renderHeader = function(view) {
    return '<span>' + this.refHeaderString() + '</span>'
            + '<span class="badge badge-info expr-collapse-button">&plusmn;</span>';
}
PerlValue.REF.prototype.renderValue = function(view) {
    return '<ul class="PerlValue"><li>' + this.value.render(view) + '</li></ul>';
}

//Regexp (from qr() ) values
PerlValue.REGEXP = function(value) {
    this.value = value.__value;
    this.refaddr = value.__refaddr;
    this.type = value.__reftype;
    this.blessed = value.__blessed;
}
PerlValue.REGEXP.prototype = new PerlValue();
PerlValue.REGEXP.prototype.renderValue = function(view) {
    return '<span class="PerlValue">m/'
            + this.escapedValue(this.value[0])
            + '/' + this.escapedValue(this.value[1])
            + '</span>';
}


PerlValue.VSTRING = function(value) {
    this.value = value.__value;
    this.refaddr = value.__refaddr;
    this.type = value.__reftype;
    this.blessed = value.__blessed;
}
PerlValue.VSTRING.prototype = new PerlValue();
PerlValue.VSTRING.prototype.renderValue = function(view) {
    return '<span class="PerlValue">v' + this.value.join('.');
}



// For rendering a value marked as 'recursive'
PerlValue.recursive = function(value) {
    this.value = value.__value;
    this.refaddr = value.__refaddr;
    this.type = value.__reftype;
    this.blessed = value.__blessed;
}
PerlValue.recursive.prototype = new PerlValue();
PerlValue.recursive.prototype.renderHeader = function(view) {
    return '<span>' + this.refHeaderString() + '</span>';
}
PerlValue.recursive.prototype.renderValue = function(view) {
    return '<span class="icon-repeat"></span> ' + this.escapedValue();
}


// For rendering tied variables
PerlValue.tied = function(value) {
    this.type = value.__reftype;
    this.refaddr = value.__refaddr;
    this.blessed = value.__blessed;
    this.value = PerlValue.parseFromEval(value.__value);
}
PerlValue.tied.prototype = new PerlValue();
PerlValue.tied.prototype.renderHeader = function(view) {
    return '<span>' + this.refHeaderString() + '</span>';
}
PerlValue.tied.prototype.renderValue = function(view) {
    if (view === 'condensed') {
        return '';
    }

    var html = '<dl class="PerlValue">';
    html += '<dt><span class="badge badge-info">tied</span></dt><dd>' + this.value.render(view) + '</dd>';
    return html + '</dl>';
}




PerlValue.prototype.refHeaderString = function() {
    var html = '';
    if (this.blessed) {
        html += this.blessed + '=';
    }
    html += this.type + '(0x' + this.refaddr.toString(16) + ')';
    return html;
}
PerlValue.prototype.renderHeader = function(view) { return '' };
PerlValue.prototype.renderValue = function(view) { return '' };
