// Copyright 2019 Linus Åkesson
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 	1. Redistributions of source code must retain the above copyright
// 	notice, this list of conditions and the following disclaimer.
//
// 	2. Redistributions in binary form must reproduce the above copyright
// 	notice, this list of conditions and the following disclaimer in the
// 	documentation and/or other materials provided with the distribution.
//
// 	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
// 	IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// 	TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
// 	PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// 	HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// 	SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// 	LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// 	DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// 	THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// 	(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// 	OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(function(){"use strict";

var b64_enc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
var b64_dec = [];

var aaengine;
var aatranscript;
var io;
var status;
var metadata;
var remoteenabled = false;
var remoteinitialized = false;
var remotepath, remotetag, remotesession, remotepos = 0;

for(var i = 0; i < b64_enc.length; i++) {
	b64_dec[b64_enc.charAt(i)] = i;
}

function decode_b64(data) {
	var array = new Uint8Array(data.length * 3 / 4);
	var i = 0, j = 0, b0, b1, b2, b3;
	while(i < data.length) {
		b0 = b64_dec[data.charAt(i++)];
		b1 = b64_dec[data.charAt(i++)];
		b2 = b64_dec[data.charAt(i++)];
		b3 = b64_dec[data.charAt(i++)];
		array[j++] = (b0 << 2) | (b1 >> 4);
		array[j++] = ((b1 & 15) << 4) | (b2 >> 2);
		array[j++] = ((b2 & 3) << 6) | b3;
	}
	if(b2 == 64) {
		array = array.slice(0, array.length - 2);
	} else if(b3 == 64) {
		array = array.slice(0, array.length - 1);
	}
	return array;
}

function encode_b64(data) {
	var str = "";
	var i = 0, j = 0, b0, b1, b2;
	while(i < data.length) {
		b0 = data[i++];
		str += b64_enc.charAt(b0 >> 2);
		if(i < data.length) {
			b1 = data[i++];
			str += b64_enc.charAt(((b0 & 3) << 4) | (b1 >> 4));
			if(i < data.length) {
				b2 = data[i++];
				str += b64_enc.charAt(((b1 & 15) << 2) | (b2 >> 6));
				str += b64_enc.charAt(b2 & 63);
			} else {
				str += b64_enc.charAt((b1 & 15) << 2) + "=";
			}
		} else {
			str += b64_enc.charAt((b0 & 3) << 4) + "==";
		}
	}
	return str;
}

function downloaddata(fname, filedata, is_url) {
	var blob;
	var url, elem;

	if(window.navigator && window.navigator.msSaveOrOpenBlob && !is_url) {
		blob = new Blob([filedata.buffer], {type: "application/octet-stream"});
		window.navigator.msSaveOrOpenBlob(blob, fname);
	} else {
		if(is_url) {
			url = filedata;
		} else {
			url = "data:application/octet-stream;base64," + encode_b64(filedata);
		}
		elem = document.createElement("a");
		elem.href = url;
		elem.setAttribute("download", fname);
		elem.innerHTML = "[click to download]";
		io.current.appendChild(elem);
		elem.click();
		io.current.removeChild(elem);
	}
}

function createdoc() {
	var top, outer, inner, btn, menu, list, line, cont, form, main, lbl, div, inp;

	top = document.getElementById("aacontainer");

	outer = document.createElement("div");
	outer.setAttribute("id", "aaouterstatus");
	top.appendChild(outer);

	btn = document.createElement("div");
	btn.setAttribute("id", "aamenubutton");
	outer.appendChild(btn);

	menu = document.createElement("div");
	menu.setAttribute("id", "aamenulines");
	btn.appendChild(menu);

	menu = document.createElement("div");
	menu.setAttribute("id", "aamenu");
	btn.appendChild(menu);

	list = document.createElement("div");
	list.setAttribute("id", "aamenulist");
	menu.appendChild(list);

	lbl = document.createElement("label");
	lbl.setAttribute("for", "aacbf");
	div = document.createElement("div");
	inp = document.createElement("input");
	inp.setAttribute("class", "aacb");
	inp.setAttribute("id", "aacbf");
	inp.setAttribute("type", "checkbox");
	inp.checked = true;
	div.appendChild(inp);
	div.appendChild(document.createTextNode("Fading text"));
	lbl.appendChild(div);
	list.appendChild(lbl);

	lbl = document.createElement("label");
	lbl.setAttribute("for", "aacbn");
	div = document.createElement("div");
	inp = document.createElement("input");
	inp.setAttribute("class", "aacb");
	inp.setAttribute("id", "aacbn");
	inp.setAttribute("type", "checkbox");
	div.appendChild(inp);
	div.appendChild(document.createTextNode("Night mode"));
	lbl.appendChild(div);
	list.appendChild(lbl);

	lbl = document.createElement("label");
	lbl.setAttribute("for", "aacba");
	div = document.createElement("div");
	inp = document.createElement("input");
	inp.setAttribute("class", "aacb");
	inp.setAttribute("id", "aacba");
	inp.setAttribute("type", "checkbox");
	div.appendChild(inp);
	div.appendChild(document.createTextNode("Always re-focus"));
	lbl.appendChild(div);
	list.appendChild(lbl);

	list.appendChild(document.createElement("hr"));

	cont = document.createElement("div");
	cont.setAttribute("id", "aarestart");
	cont.innerHTML = "Restart game";
	list.appendChild(cont);

	cont = document.createElement("div");
	cont.setAttribute("id", "aasavescript");
	cont.innerHTML = "Save transcript";
	list.appendChild(cont);

	cont = document.createElement("div");
	cont.setAttribute("id", "aasavestory");
	cont.innerHTML = "Save story file";
	list.appendChild(cont);

	list.appendChild(document.createElement("hr"));

	cont = document.createElement("div");
	cont.setAttribute("id", "aaaboutopen");
	cont.innerHTML = "About";
	list.appendChild(cont);

	inner = document.createElement("div");
	inner.setAttribute("id", "aastatus");
	outer.appendChild(inner);

	outer = document.createElement("div");
	outer.setAttribute("id", "aastatusborder");
	top.appendChild(outer);

	outer = document.createElement("div");
	outer.setAttribute("id", "aaaboutouter");
	top.appendChild(outer);

	inner = document.createElement("div");
	inner.setAttribute("id", "aaaboutinner");
	outer.appendChild(inner);

	line = document.createElement("div");
	line.setAttribute("class", "aaaboutline");
	line.setAttribute("id", "aaaboutmeta");
	inner.appendChild(line);

	inner.appendChild(document.createElement("hr"));

	cont = document.createElement("a");
	cont.setAttribute("id", "aaaboutlink");
	cont.setAttribute("target", "_blank");
	cont.setAttribute("href", "https://linusakesson.net/dialog/aamachine/");
	cont.innerHTML = "&Aring;-machine web interpreter v0.3.1";
	line = document.createElement("div");
	line.setAttribute("class", "aaaboutline");
	line.appendChild(cont);
	inner.appendChild(line);

	inner.appendChild(document.createElement("hr"));

	cont = document.createElement("div");
	cont.setAttribute("class", "aalink");
	cont.setAttribute("id", "aaaboutclose");
	cont.innerHTML = "Close";
	line = document.createElement("div");
	line.setAttribute("class", "aaaboutline");
	line.appendChild(cont);
	inner.appendChild(line);

	form = document.createElement("form");
	form.setAttribute("id", "aaform");
	form.setAttribute("autocomplete", "off");
	top.appendChild(form);

	main = document.createElement("div");
	main.setAttribute("id", "aamain");
	main.setAttribute("aria-live", "polite");
	form.appendChild(main);

	inp = document.createElement("input");
	inp.setAttribute("id", "aainput");
	inp.setAttribute("type", "text");
	inp.setAttribute("value", "");
	inp.setAttribute("autocomplete", "off");
	inp.setAttribute("spellcheck", "false");
	inp.setAttribute("autocorrect", "off");
	inp.setAttribute("aria-live", "off");
	main.appendChild(inp);
}

function handleremote() {
	var fname, now, dstr, tstr, pending;

	if(remoteenabled) {
		if(!remoteinitialized) {
			now = new Date();
			dstr = now.getFullYear().toString().slice(2) + ("0" + (now.getMonth() + 1)).slice(-2) + ("0" + now.getDate()).slice(-2);
			tstr = ("0" + now.getHours()).slice(-2) + ("0" + now.getMinutes()).slice(-2);
			if(!remotetag) {
				remotetag = aaengine.get_metadata().title.replace(/[^a-zA-Z0-9]+/g, "-");
			}
			remotesession = remotetag + "-" + dstr + "-" + tstr + "-" + Math.ceil(Math.random()*1000);
			remoteinitialized = true;
		}
		if(remotepos < aatranscript.full.length) {
			pending = aatranscript.full.slice(remotepos);
			remotepos = aatranscript.full.length;
			$.ajax({
				type: "POST",
				url: remotepath,
				data: {
					data: {
						session: remotesession,
						text: pending
					}
				},
				error: function(c) {
					remoteenabled = false;
				}
			});
		}
	}
}

window.run_game = function(story64, options) {
	var storybytes = decode_b64(story64);

	if(options && options.aaLogServerPath) {
		remotepath = options.aaLogServerPath;
		remotetag = options.aaLogTag;
		if(window.location.href.search('nofeedback') == -1) {
			remoteenabled = true;
		}
	}

	aatranscript = {
		did_line: false,
		did_par: false,
		full: "",
		line: function() {
			if(!this.did_par && !this.did_line) {
				this.print("\n");
				this.did_line = true;
			}
		},
		par: function() {
			if(!this.did_par) {
				if(!this.did_line) this.print("\n");
				this.print("\n");
				this.did_par = true;
			}
		},
		print: function(str) {
			this.full += str;
			this.did_line = false;
			this.did_par = false;
		},
	};

	io = {
		in_par: false,
		after_text: false,
		status_visible: false,
		in_status: false,
		n_inner: 0,
		current: document.getElementById("aamain"),
		divs: [],
		aainput: null,
		history: [],
		histpos: 0,
		protected_inp: "",
		transcript: aatranscript,
		sticky_focus: false,
		always_refocus: false,
		scroll_anchor: null,
		flush: function() {
		},
		reset: function() {
			this.status_visible = false;
			this.in_status = false;
			this.clear_all();
			this.transcript.par();
		},
		clear_all: function() {
			if(!this.in_status) {
				var div = document.getElementById("aastatus");
				$(div).empty();
				$(div).css("height", "0em");
				this.clear();
			}
		},
		clear: function() {
			if(!this.in_status) {
				$(this.aainput).detach();
				this.scroll_anchor = null;
				this.current = document.getElementById("aamain");
				$(this.current).empty();
				this.in_par = false;
				this.after_text = false;
				this.n_inner = 0;
				this.divs = [];
				this.transcript.par();
			}
		},
		ensure_par: function() {
			if(!this.in_par) {
				var p = document.createElement("p");
				if(this.after_text) {
					p.style["margin-top"] = "1.2em";
				}
				if(!document.getElementById("aacbf").checked) {
					p.style["animation-name"] = "none";
				}
				if(document.getElementById("aacbn").checked) {
					p.style.color = "#ccc";
				}
				this.current.appendChild(p);
				this.current = p;
				this.in_par = true;
				this.after_text = false;
			}
		},
		print: function(str) {
			this.ensure_par();
			this.current.appendChild(document.createTextNode(str));
			this.after_text = true;
			if(!this.in_status) {
				this.transcript.print(str);
			}
		},
		space: function() {
			this.print(" ");
			this.after_text = true;
		},
		space_n: function(n) {
			var span, i;
			this.ensure_par();
			span = document.createElement("span");
			$(span).css("display", "inline-block");
			$(span).css("width", n + "ch");
			this.current.appendChild(span);
			this.after_text = true;
			if(!this.in_status) {
				for(i = 0; i < n; i++) {
					this.transcript.print(" ");
				}
			}
		},
		leave_inner: function() {
			this.unstyle();
			if(this.in_par) {
				this.current = this.current.parentNode;
				this.in_par = false;
			}
			this.after_text = false;
		},
		line: function() {
			if(this.in_par) {
				this.current.appendChild(document.createElement("br"));
			}
			if(!this.in_status) {
				this.transcript.line();
			}
		},
		par: function() {
			this.unstyle();
			if(this.in_par) {
				this.current = this.current.parentNode;
				this.in_par = false;
			}
			if(!this.in_status) {
				this.transcript.par();
			}
		},
		setstyle: function(s) {
			var span;
			if(!this.in_status) {
				if(s & 2) {
					this.ensure_par();
					span = document.createElement("span");
					span.style["font-weight"] = "bold";
					this.current.appendChild(span);
					this.current = span;
					this.n_inner++;
				}
				if(s & 4) {
					this.ensure_par();
					span = document.createElement("span");
					span.style["font-style"] = "italic";
					this.current.appendChild(span);
					this.current = span;
					this.n_inner++;
				}
				if(s & 8) {
					this.ensure_par();
					span = document.createElement("span");
					span.style["font-family"] = "webkitworkaround, monospace";
					span.style["font-size"] = "1em";
					this.current.appendChild(span);
					this.current = span;
					this.n_inner++;
				}
			}
		},
		resetstyle: function(s) {
			var span;
			if(!this.in_status) {
				if(s & 2) {
					this.ensure_par();
					span = document.createElement("span");
					span.style["font-weight"] = "normal";
					this.current.appendChild(span);
					this.current = span;
					this.n_inner++;
				}
				if(s & 4) {
					this.ensure_par();
					span = document.createElement("span");
					span.style["font-style"] = "normal";
					this.current.appendChild(span);
					this.current = span;
					this.n_inner++;
				}
				if(s & 8) {
					this.ensure_par();
					span = document.createElement("span");
					span.style["font-family"] = "Georgia, serif";
					this.current.appendChild(span);
					this.current = span;
					this.n_inner++;
				}
			}
		},
		unstyle: function() {
			while(this.n_inner) {
				this.current = this.current.parentNode;
				this.n_inner--;
			}
		},
		enter_div: function(id) {
			var k, sty;
			this.leave_inner();
			var div = document.createElement("div");
			sty = this.styles[id];
			for(k in sty) {
				if(sty.hasOwnProperty(k)) {
					div.style[k] = sty[k];
				}
			}
			this.current.appendChild(div);
			this.divs.push(this.current);
			this.current = div;
			if(!this.in_status) {
				this.transcript.line();
			}
		},
		leave_div: function(id) {
			this.leave_inner();
			this.divs.pop();
			this.current = this.current.parentNode;
			if(!this.in_status) {
				this.transcript.line();
			}
		},
		enter_status: function(id) {
			this.leave_inner();
			if(!this.in_status) {
				var div, sty, k;
				this.divs.push(this.current);
				$(this.aainput).detach();
				div = document.getElementById("aastatus");
				$(div).empty();
				sty = this.styles[id];
				for(k in sty) {
					if(sty.hasOwnProperty(k)) {
						div.style[k] = sty[k];
					}
				}
				this.current = div;
				this.in_status = true;
			}
		},
		leave_status: function(id) {
			this.leave_inner();
			if(this.in_status) {
				this.current = this.divs.pop();
				this.after_text = true;
				if(!this.status_visible) {
					document.getElementById("aastatus").style.display = "block";
					var b = document.getElementById("aastatusborder");
					b.style["animation-name"] = "fadein";
					b.style["animation-duration"] = ".9s";
					b.style["animation-delay"] = ".1s";
					this.status_visible = true;
				}
				//this.adjust_size();
				this.in_status = false;
			}
		},
		enter_link: function(str) {
			var span, old;
			this.ensure_par();
			span = document.createElement("span");
			$(span).addClass("aalink");
			span.href = "#0";
			this.current.appendChild(span);
			$(span).on("mouseover", function() {
				if(status == aaengine.status.get_input) {
					old = io.protected_inp;
					if(old && old.length && old[old.length - 1] != " ") old += " ";
					$(io.aainput).val(old + str);
				}
			});
			$(span).on("mouseout", function() {
				if(status == aaengine.status.get_input) {
					$(io.aainput).val(io.protected_inp);
				}
			});
			$(span).on("click", function() {
				if(status == aaengine.status.get_input) {
					old = io.protected_inp;
					if(old && old.length && old[old.length - 1] != " ") old += " ";
					$(io.aainput).val(old + str);
					io.sticky_focus = false;
					$(io.aainput).submit();
				}
				return false;
			});
			this.current = span;
		},
		leave_link: function() {
			this.current = this.current.parentNode;
		},
		transform_url: function(url) {
			if(url.match(/^file:/i)) {
				return url.replace(/^file:/i, 'resources/');
			} else {
				return url;
			}
		},
		enter_link_res: function(res) {
			var a;

			this.ensure_par();
			a = document.createElement("a");
			$(a).addClass("aalink");
			a.href = this.transform_url(res.url);
			a.setAttribute("target", "_blank");
			this.current.appendChild(a);
			this.current = a;
		},
		leave_link_res: function() {
			this.current = this.current.parentNode;
		},
		embed_res: function(res) {
			var img;

			if(this.can_embed_res(res)) {
				this.ensure_par();
				img = document.createElement("img");
				img.src = this.transform_url(res.url);
				img.setAttribute("alt", res.alt);
				this.current.appendChild(img);
			} else {
				this.print("[");
				this.print(res.alt);
				this.print("]");
			}
		},
		can_embed_res: function(res) {
			return !!res.url.match(/\.(png|jpe?g)$/i);
		},
		adjust_size: function() {
			var aamain = $("#aamain");
			var newheight = $(window).innerHeight() - $("#aaouterstatus").outerHeight() - (aamain.outerHeight(true) - aamain.innerHeight()) - 40;
			aamain.height(newheight);
		},
		progressbar: function(p, total) {
			this.leave_inner();
			p = p * 100 / total;
			if(p < 0) p = 0;
			if(p > 100) p = 100;
			var outer = $("<div/>").addClass("aaouterprogress").appendTo(this.current);
			$("<div/>").addClass("aaprogress").appendTo(outer).css("width", p + "%");
		},
		trace: function(str) {
		},
		script_on: function() {
			this.line();
			this.print("The web interpreter keeps a local transcript at all times. ");
			this.print("It can be downloaded from the menu in the top-right corner. ");
			this.print("The feature cannot be manually enabled or disabled.");
			this.line();
			return false;
		},
		script_off: function() {
		},
		save: function(filedata) {
			var fname, now, dstr, tstr;
			now = new Date();
			dstr = now.getFullYear().toString().slice(2) + ("0" + (now.getMonth() + 1)).slice(-2) + ("0" + now.getDate()).slice(-2);
			tstr = ("0" + now.getHours()).slice(-2) + ("0" + now.getMinutes()).slice(-2);
			fname = aaengine.get_metadata().title.replace(/[^a-zA-Z0-9]+/g, "-") + "-" + dstr + "-" + tstr + ".aasave";
			downloaddata(fname, filedata, false);
			return true;
		},
		restore: function() {
			var inp = document.createElement("input"), cancel = document.createElement("input");
			function bailout() {
				$(cancel).detach();
				if(status == aaengine.status.restore) {
					status = aaengine.vm_restore(null);
					io.activate_input();
				}
			}
			inp.setAttribute("type", "file");
			inp.setAttribute("accept", ".aasave");
			cancel.setAttribute("type", "button");
			cancel.setAttribute("value", "Cancel");
			$(inp).on("change", function(event) {
				var reader;
				if(event.target.files.length) {
					reader = new FileReader();
					reader.onload = function() {
						$(cancel).detach();
						if(status == aaengine.status.restore) {
							status = aaengine.vm_restore(new Uint8Array(reader.result));
							io.activate_input();
						}
					};
					reader.onabort = bailout;
					reader.onerror = bailout;
					reader.readAsArrayBuffer(event.target.files[0]);
				} else {
					bailout();
				}
			});
			$(cancel).on("click", function() {
				bailout();
			});
			$(this.aainput).detach();
			this.current.appendChild(inp);
			this.current.appendChild(cancel);
			inp.click();
			this.current.removeChild(inp);
		},
		activate_input: function() {
			this.ensure_par();
			this.adjust_size();
			this.current.appendChild(this.aainput);
			$(this.aainput).val("");
			this.protected_inp = "";
			this.aainput.style.maxWidth = "100px";
			this.aainput.style.display = "inline-block";
			//$(this.aainput).val($(this.current).width() + ", " + $(this.aainput).position().left);
			this.aainput.style.maxWidth = ($(this.current).width() - $(this.aainput).position().left) + "px";
			handleremote();
			this.maybe_focus();
			if(status == aaengine.status.quit || status == aaengine.status.restore) {
				$(this.aainput).detach();
			}
		},
		maybe_focus: function() {
			if(this.sticky_focus || this.always_refocus) {
				this.aainput.focus();
			} else if(this.scroll_anchor) {
				this.scroll_anchor.scrollIntoView(true);
			} else {
				this.aainput.scrollIntoView();
			}
		},
		hist_add: function(str) {
			this.histpos = this.history.length;
			if(str && !(this.history.length && str == this.history[this.history.length - 1])) {
				this.history[this.histpos++] = str;
				if(this.history.length > 50) {
					this.history = this.history.slice(1);
					this.histpos--;
				}
			}
		},
		hist_up: function() {
			if(this.histpos) {
				$(this.aainput).val((this.protected_inp = this.history[--this.histpos]));
			}
		},
		hist_down: function() {
			if(this.histpos < this.history.length - 1) {
				$(this.aainput).val((this.protected_inp = this.history[++this.histpos]));
			} else if(this.histpos == this.history.length - 1) {
				$(this.aainput).val((this.protected_inp = ""));
				this.histpos++;
			}
		}
	};

	createdoc();

	io.aainput = document.getElementById("aainput");

	$("#aainput").on('focus', function() {
		io.sticky_focus = true;
	});

	$("#aainput").on('input', function() {
		if(status == aaengine.status.get_key) {
			var str = $(io.aainput).val();
			io.leave_inner();
			io.after_text = true;
			status = aaengine.vm_proceed_with_key((str && str.length)? str.charCodeAt(0) : aaengine.keys.KEY_RETURN);
			io.activate_input();
		} else if(status == aaengine.status.get_input) {
			io.protected_inp = $(io.aainput).val();
		}
	});

	$("#aainput").on('keydown', function(code) {
		if(code.keyCode == 27) {
			io.aainput.blur();
		} else if(status == aaengine.status.get_input) {
			if(code.keyCode == 38) {
				io.hist_up();
				return false;
			} else if(code.keyCode == 40) {
				io.hist_down();
				return false;
			}
		}
	});

	$("#aaform").on('submit', function() {
		var str = $(io.aainput).val();
		if(status == aaengine.status.get_input) {
			io.hist_add(str);
			io.aainput.style.display = "none";
			io.scroll_anchor = io.current;
			io.current.appendChild(document.createTextNode(str));
			io.transcript.print(str);
			io.transcript.line();
			io.current.style["margin-bottom"] = ".3em";
			io.after_text = false;
			io.leave_inner();
			status = aaengine.vm_proceed_with_input(str);
			io.activate_input();
		} else if(status == aaengine.status.get_key) {
			io.leave_inner();
			io.after_text = true;
			io.scroll_anchor = null;
			status = aaengine.vm_proceed_with_key((str && str.length)? str.charCodeAt(0) : aaengine.keys.KEY_RETURN);
			io.activate_input();
		}
		return false;
	});

	$(document).on("click", function() {
		document.getElementById("aamenu").style.display = "none";
		document.getElementById("aaaboutouter").style.display = "none";
	});

	$("#aamain").on("click", function() {
		document.getElementById("aamenu").style.display = "none";
	});

	function update_night() {
		if(document.getElementById("aacbn").checked) {
			$("body").css("background-color", "#000");
			$("p").css("color", "#ccc");
			io.aainput.style.color = "#ccc";
			$("#aastatusborder").css("background-color", "#ccc");
		} else {
			$("body").css("background-color", "#eee");
			$("p").css("color", "#000");
			io.aainput.style.color = "#000";
			$("#aastatusborder").css("background-color", "#000");
		}
		io.maybe_focus();
	}

	$("#aacbn").on("change", function() {
		update_night();
	});

	$("#aacbf").on("change", function() {
		io.maybe_focus();
	});

	$("#aacba").on("change", function() {
		io.always_refocus = document.getElementById("aacba").checked;
		io.maybe_focus();
	});

	$("#aamenulines").on('click', function() {
		var menu = document.getElementById("aamenu");
		if(menu.style.display == "block") {
			menu.style.display = "none";
		} else {
			menu.style.display = "block";
		}
		if(window.getSelection) {
			window.getSelection().removeAllRanges();
		} else if(document.selection) {
			document.selection.empty();
		}
		return false;
	});

	$("#aarestart").on("click", function() {
		document.getElementById("aamenu").style.display = "none";
		$(this.aainput).detach();
		io.reset();
		status = aaengine.async_restart();
		io.activate_input();
		return false;
	});

	$("#aasavescript").on("click", function() {
		var fname, now, dstr, tstr;
		var bytes = [], i, ch;
		now = new Date();
		dstr = now.getFullYear().toString().slice(2) + ("0" + (now.getMonth() + 1)).slice(-2) + ("0" + now.getDate()).slice(-2);
		tstr = ("0" + now.getHours()).slice(-2) + ("0" + now.getMinutes()).slice(-2);
		fname = aaengine.get_metadata().title.replace(/[^a-zA-Z0-9]+/g, "-") + "-" + dstr + "-" + tstr + ".txt";
		for(i = 0; i < aatranscript.full.length; i++) {
			ch = aatranscript.full.charCodeAt(i);
			if(ch < 0x80) {
				bytes.push(ch);
			} else if(ch < 0x800) {
				bytes.push(0xc0 | (ch >> 6));
				bytes.push(0x80 | (ch & 0x3f));
			} else {
				bytes.push(0xe0 | (ch >> 12));
				bytes.push(0x80 | ((ch >> 6) & 0x3f));
				bytes.push(0x80 | (ch & 0x3f));
			}
		}
		document.getElementById("aamenu").style.display = "none";
		downloaddata(fname, new Uint8Array(bytes), false);
		return false;
	});

	$("#aasavestory").on("click", function() {
		var fname, elem;

		document.getElementById("aamenu").style.display = "none";
		fname = aaengine.get_metadata().title.replace(/[^a-zA-Z0-9]+/g, "-") + ".aastory";
		elem = document.createElement("a");
		elem.href = 'resources/' + fname;
		elem.setAttribute('download', fname);
		elem.setAttribute('target', '_blank');
		elem.innerHTML = "[click to download]";
		io.current.appendChild(elem);
		elem.click();
		io.current.removeChild(elem);
		return false;
	});

	$(window).resize(function() {
		io.adjust_size();
	});

	update_night();

	aaengine = window.aaengine;
	aaengine.prepare_story(storybytes, io, undefined, true, false);
	io.styles = aaengine.get_styles();

	metadata = aaengine.get_metadata();
	var div = document.getElementById("aaaboutmeta");
	$(document).attr("title", metadata.title);
	div.appendChild(document.createTextNode(metadata.title));
	if(metadata.author) {
		div.appendChild(document.createElement("br"));
		div.appendChild(document.createTextNode(metadata.author));
	}
	div.appendChild(document.createElement("br"));
	div.appendChild(document.createTextNode("Release " + metadata.release));
	if(metadata.date) {
		div.appendChild(document.createTextNode(", " + metadata.date));
	}
	if(metadata.blurb) {
		div.appendChild(document.createElement("hr"));
		div.appendChild(document.createTextNode(metadata.blurb));
	}
	$("#aaaboutopen").on("click", function() {
		document.getElementById("aaaboutouter").style.display = "block";
		document.getElementById("aamenu").style.display = "none";
		return false;
	});
	$("#aaaboutclose").on("click", function() {
		document.getElementById("aaaboutouter").style.display = "none";
		return false;
	});
	$("#aaaboutinner").on("click", function() {
		return false;
	});
	$("#aaaboutlink").on("click", function(e) {
		e.stopPropagation();
		return true;
	});

	status = aaengine.vm_start();
	io.activate_input();
};

})();
