// Represents a Perl value
function PerlValue() { }
PerlValue.prototype.render = function() {
    return this.renderHeader() + this.renderValue();
}

PerlValue.parseFromEval = function(value) {
    var pv;
    // null _is_ an object, but we want to represent it as a scalar/undef
    if ((typeof value === 'object') && (value !== undefined) && (value !== null)) {
        pv = new PerlValue[ value.__reftype](value);
    } else {
        pv = new PerlValue.scalar(value);
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
PerlValue.exception.prototype.render = function() {
    return '<span class="label label-important PerlValue">'+this.value+'</span>';
};

// simple scalar values
PerlValue.scalar = function(value) {
    this.value = value;
    this.type = 'scalar';
}
PerlValue.scalar.prototype = new PerlValue();
PerlValue.scalar.prototype.render = function() {
    if ((this.value === undefined) || (this.value === null)) {
        return '<span class="label PerlValue"><i>undef</i></span>';
    } else {
        return '<span class="PerlValue">' + this.value + '</span>';
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
PerlValue.SCALAR.prototype.render = function() {
    return '<span>'
            + this.refHeaderString()
            + '</span><span class="PerlValue">'
            + this.value.render()
            + '</span>';
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
PerlValue.ARRAY.prototype.renderHeader = function() {
    return '<span>' + this.refHeaderString() + '</span>'
            + ' <span class="badge badge-info expr-collapse-button">'
            + this.count +'</span>';
}
PerlValue.ARRAY.prototype.renderValue = function() {
    var html = '<dl>';
    for(var i = 0; i < this.value.length; i++) {
        html += '<dt>' + i + '</dt><dd>'
                + this.value[i].render() + '</dd>';
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
PerlValue.HASH.prototype.renderHeader = function() {
    return '<span>' + this.refHeaderString() + '</span>'
            + ' <span class="badge badge-info expr-collapse-button">'
            + this.count + '</span>';
}
PerlValue.HASH.prototype.renderValue = function() {
    var html = '<dl>',
        k;
    for (key in this.value) {
        html += '<dt>' + key + '</dt><dd>' + this.value[key].render() + '</dd>';
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
        if (value.__value.hasOwnProperty(k)) {
            this.value[k] = PerlValue.parseFromEval(value.__value[k]);
        }
    }
}
PerlValue.GLOB.prototype = new PerlValue();
PerlValue.GLOB.prototype.renderHeader = function() {
    return '<span>' + this.refHeaderString() + '</span>'
            + ' <span class="badge badge-info expr-collapse-button">&plusmn;</span>';
}
PerlValue.GLOB.prototype.renderValue = function() {
    var html = '<dl>',
        k;
    for (k in this.value) {
        html += '<dt><span class="label label-success">' + k + '</span></dt><dd>'
                + this.value[k].render() + '</dd>';
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
PerlValue.CODE.prototype.render = function() {
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
PerlValue.REF.prototype.renderHeader = function() {
    return '<span>' + this.refHeaderString() + '</span>'
            + '<span class="badge badge-info expr-collapse-button">&plusmn;</span>';
}
PerlValue.REF.prototype.renderValue = function() {
    return '<ul><li>' + this.value.render() + '</li></ul>';
}




PerlValue.prototype.refHeaderString = function() {
    var html = '';
    if (this.blessed) {
        html += this.blessed + '=';
    }
    html += this.type + '(0x' + this.refaddr.toString(16) + ')';
    return html;
}
