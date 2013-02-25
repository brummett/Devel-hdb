function FileManager(messageHandler) {
    this.files = {};
    this.messageHandler = messageHandler;
    this.programListingTemplate = Handlebars.compile( $('#program-listing-template').html() );

    messageHandler.addHandler('sourcefile', this.sourceFileLoaded.bind(this));
}

FileManager.prototype.loadFile = function(filename) {
    if (! (filename in this.files)) {
        var d = $.Deferred();
        $.ajax({url: 'sourcefile',
                type: 'GET',
                data: { f: filename },
                success: this.messageHandler.consumer,
                // TODO replace with something better
                error: function() { alert('Cannot load file '+filename); }
            });

        this.files[filename] = d;
    }
    return this.files[filename].promise()
};

FileManager.prototype.sourceFileLoaded = function(data) {
    var filename = data.filename,
        templateData, $elt, i;

    if (data.lines.length) {
        // File is loaded
        templateData = { filename: filename, rows: [] };
        for (i = 0; i < data.lines.length; i++) {
            templateData.rows.push({ line: i+1, code: data.lines[i][0], unbreakable: !data.lines[i][1]});
        }
        var $elt = $( this.programListingTemplate(templateData) );
        this.files[filename].resolve($elt);

    } else {
        // Not loaded
        this.files[filename].reject();

        // remove the deferred object so we can ask for it again later
        delete this.files[filename];
    }
};
