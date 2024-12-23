(function(){"use strict";

const fs = require('fs');
const readline = require('readline');
const aaengine = require('./engine.js');

var status;

const io = {
	hidden: false,
	newlines: 0,
	pending_spaces: 0,
	pending_word: "",
	xpos: 0,
	vspace_n: function(n) {
		n = Math.floor(n) + 1;
		while(this.newlines < n) {
			process.stdout.write("\n");
			this.newlines++;
		}
		this.xpos = 0;
		this.pending_spaces = 0;
	},
	flush: function() {
		if(this.xpos + this.pending_spaces + this.pending_word.length > 80) {
			this.vspace_n(0);
		}
		while(this.pending_spaces) {
			if(this.xpos) {
				process.stdout.write(" ");
				this.xpos++;
			}
			this.pending_spaces--;
		}
		if(this.pending_word.length) {
			process.stdout.write(this.pending_word);
			this.xpos += this.pending_word.length;
			this.newlines = 0;
			this.pending_word = "";
		}
	},
	reset: function() {
		this.hidden = false;
		this.pending_word = "";
		this.pending_spaces = 0;
		this.xpos = 0;
		this.newlines = 1;
	},
	clear: function() {
		this.par();
	},
	clear_all: function() {
		this.par();
	},
	print: function(str) {
		if(!this.hidden) {
			for(let i = 0; i < str.length; i++) {
				if(str[i] == ' ') {
					this.flush();
					this.pending_spaces++;
				} else if(str[i] == '-') {
					this.pending_word += str[i];
					this.flush();
				} else {
					this.pending_word += str[i];
				}
			}
		}
	},
	space: function() {
		if(!this.hidden) {
			this.print(" ");
		}
	},
	space_n: function(n) {
		if(!this.hidden) {
			this.flush();
			if(n > 80 - this.xpos) n = 80 - this.xpos;
			for(var i = 0; i < n; i++) {
				process.stdout.write(" ");
				this.xpos++;
			}
			this.newlines = 0;
		}
	},
	line: function() {
		if(!this.hidden) {
			this.flush();
			this.vspace_n(0);
		}
	},
	par: function() {
		if(!this.hidden) {
			this.flush();
			this.vspace_n(1);
		}
	},
	setstyle: function(s) {
	},
	resetstyle: function(s) {
	},
	unstyle: function() {
	},
	parse_em: function(id, key, defvalue) {
		if(id >= 0) {
			let str = this.styles[id][key];
			if(str) {
				let arr = /^ *(\d+)em */.exec(str);
				if(arr) return parseInt(arr[1], 10);
			}
		}
		return defvalue;
	},
	enter_div: function(id) {
		if(!this.hidden) {
			this.flush();
			this.vspace_n(this.parse_em(id, "margin-top", 0));
		}
	},
	leave_div: function(id) {
		if(!this.hidden) {
			this.flush();
			this.vspace_n(this.parse_em(id, "margin-bottom", 0));
		}
	},
	enter_status: function(id) {
		this.line();
		this.hidden = true;
	},
	leave_status: function(id) {
		this.hidden = false;
	},
	enter_link: function(str) {
	},
	leave_link: function() {
	},
	enter_link_res: function(res) {
	},
	leave_link_res: function() {
	},
	embed_res: function(res) {
		this.print("[");
		this.print(res.alt);
		this.print("]");
	},
	can_embed_res: function(res) {
		return false;
	},
	progressbar: function(p, total) {
		if(!this.hidden) {
			this.enter_div(-1);
			this.print(p + " (" + total + ")");
			this.leave_div(-1);
		}
	},
	trace: function(str) {
		if(!this.hidden) {
			this.enter_div(-1);
			process.stdout.write(str);
			this.xpos = str.length;
			this.newlines = 0;
			this.leave_div(-1);
		}
	},
	script_on: function() {
		return false;
	},
	script_off: function() {
	},
	save: function(filedata) {
		fs.writeFileSync("saved-game.aasave", filedata);
		return true;
	},
	restore: function() {
		fs.readFile("saved-game.aasave", function(err, data) {
			if(status == aaengine.status.restore) {
				if(err) data = null;
				status = aaengine.vm_restore(data);
			}
		});
	}
};

const rlif = readline.createInterface({
	input: process.stdin,
	output: process.stdout,
	terminal: true,
	crlfDelay: Infinity});

var filename, seed;
if(process.argv[2] == "-s") {
	seed = parseInt(process.argv[3]);
	filename = process.argv[4];
} else {
	filename = process.argv[2];
}

var storyfile = fs.readFileSync(filename);

aaengine.prepare_story(storyfile, io, seed, false, true);
io.styles = aaengine.get_styles();

status = aaengine.vm_start();
if(status == aaengine.status.quit) {
	io.line();
	io.flush();
	process.exit(0);
}

rlif.on('line', (line) => {
	if(status == aaengine.status.get_key) {
		for(var i = 0; i < line.length && status == aaengine.status.get_key; i++) {
			status = aaengine.vm_proceed_with_key(line.charCodeAt(i));
		}
		if(status == aaengine.status.get_key) {
			status = aaengine.vm_proceed_with_key(aaengine.keys.KEY_RETURN);
		}
	} else if(status == aaengine.status.get_input) {
		io.xpos = 0;
		io.pending_spaces = 0;
		io.newlines = 1;
		status = aaengine.vm_proceed_with_input(line);
	}
	if(status == aaengine.status.quit) {
		io.line();
		io.flush();
		process.exit(0);
	}
});

rlif.on('close', () => {
	io.line();
	io.flush();
});

})();
