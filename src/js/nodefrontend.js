(function(){"use strict";

const VERSION = "1.0.0";

const fs = require('fs');
const readline = require('readline');
const aaengine = require('./engine.js');
var minimist;
try {
	minimist = require('minimist');
} catch(e) {
	minimist = require('./minimist.js'); // Include a local copy to reduce dependencies
}
var argv = minimist(process.argv.slice(2));

var status;

const io = {
	hidden: false,
	newlines: 0,
	pending_spaces: 0,
	pending_word: "",
	xpos: 0,
	width: 80,
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
		if(this.width > 0 && this.xpos + this.pending_spaces + this.pending_word.length > this.width) {
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
	clear_links: function() {
	},
	clear_old: function() {
	},
	clear_div: function() {
	},
	clear_status: function() {
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
	nbsp: function() {
		if(!this.hidden) {
			this.pending_word += " ";
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
			if(this.width > 0 && n > this.width - this.xpos) {
				n = this.width - this.xpos;
			}
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
	enter_span: function(id) {
	},
	leave_span: function() {
	},
	enter_status: function(area, id) {
		this.line();
		this.hidden = true;
	},
	leave_status: function() {
		this.hidden = false;
	},
	have_links: function() {
		return false;
	},
	enter_link: function(str) {
	},
	leave_link: function() {
	},
	enter_link_res: function(res) {
	},
	leave_link_res: function() {
	},
	enter_self_link: function() {
	},
	leave_self_link: function() {
	},
	leave_all: function() {
		this.line();
		this.hidden = false;
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
			let full = 0;
			if(this.width <= 0) {
				full = 80 - 2; // End caps
			} else {
				full = this.width - 2;
			}
			let first = Math.round(full * (p / total));
			let second = full - first;
			this.enter_div(-1);
			this.print("[");
			for(let i=0; i<first; i++) this.print("=");
			for(let i=0; i<second; i++) this.print(" ");
			this.print("]");
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

const usage = function() {
	console.log("Usage: aamrun [OPTIONS] file.aastory");
	console.log("    -s            Set random seed");
	console.log("    -w            Set screen width (default 80)");
	console.log("    -h, --help    Show this message");
	console.log("    -v, -V        Show version and exit");
}

if(argv.v || argv.V) {
	console.log("Å-machine Node frontend version " + VERSION);
	process.exit(0);
}
if(argv._.length != 1) {
	console.error("ERROR: Exactly one filename must be specified");
	usage();
	process.exit(1);
}
if(argv.h || argv.help) {
	usage();
	process.exit(0);
}

try {
	if(argv.s) {
		seed = parseInt(argv.s);
	}
	if(argv.w) {
		io.width = parseInt(argv.w);
	}
} catch(e) {
	console.error("ERROR: Unable to parse options: " + e);
	process.exit(1);
}

filename = argv._[0];

try {
	var storyfile = fs.readFileSync(filename);
} catch(e) {
	console.error("ERROR: Unable to read file " + filename + ": " + e);
	process.exit(1);
}

aaengine.prepare_story(storyfile, io, seed, true, false, false);
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
		//console.log(aaengine.mem_info());
		io.line();
		io.flush();
		process.exit(0);
	}
});

rlif.on('close', () => {
	//console.log(aaengine.mem_info());
	io.line();
	io.flush();
});

})();
