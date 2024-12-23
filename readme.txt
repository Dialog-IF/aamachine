This textfile uses UTF-8 encoding.

This archive contains version 0.4 of the Å-machine specification, and version
0.4.1 of the tools and official interpreters.

The following interpreters are included:

	* Javascript engine, web frontend.
	* Javascript engine, Node.js frontend.
	* 6502 engine, Commodore 64 frontend.
	* 6502 engine, aambox6502 frontend.

Version number:

	The version number has three parts:

	* The first part changes when there are compatibility-breaking changes
	to the specification.

	* The second part changes when there are backwards-compatible changes
	to the specification (i.e. a 0.4 interpreter must be able to run any
	0.1 story), or when errors are corrected in the specification document.

	* The third part is incremented when the tools are improved without
	changing the specification.

About the Å-machine:

	The Å-machine is a virtual machine for delivering interactive stories.
	It is inspired by the Z-machine; the letter Å (pronounced [ɔː], like
	the English word “awe”) follows Z in the Swedish alphabet.

	In international contexts, å can be transcribed into aa, as in “The
	Aa-machine”.

	The Å-machine is designed for stories implemented in the Dialog
	programming language. The Dialog compiler can produce Å-machine story
	files starting with version 0g/01. The filename ending is .aastory.
	Support for the widely used and historically important Z-machine
	remains, and will not go away. But stories compiled for the Å-machine
	look better on the web, and are smaller and faster on vintage hardware.

	In a sense, the Å-machine is to Dialog what Glulx is to Inform 7. It
	eliminates the tight restrictions on story size, and extends the basic
	functionality with a carefully balanced set of new features. But the
	Å-machine is designed to run the same stories on everything from 8-bit
	systems to modern web browsers. Data structures and encodings are
	economical, and the overall word size has not increased. Large stories
	are supported, but small stories still have a very compact binary
	representation.

	Compared to the Z-machine and Glulx, the Å-machine operates at a higher
	level of abstraction. This improves performance on vintage hardware,
	both by making story files smaller, which improves loading times, and
	by allowing larger chunks of computation to be implemented as native
	machine code. The downside is that the virtual machine is more tightly
	coupled to the idiosyncracies of a particular high-level language, in
	this case Dialog.

	Currently, two separate Å-machine interpreters exist. One is
	implemented in javascript, and the other is implemented in 6502
	assembler. Each must be combined with a frontend that handles input,
	output, and other platform-specific details.

	Two frontends for the javascript engine are provided: A web frontend
	based on jquery, for publishing stories online, and a Node.js frontend
	for running automated tests. Two frontends for the 6502 engine are
	provided: One for the Commodore 64 home computer (equipped with a
	1541-compatible floppy drive), and one for an imaginary 6502-based
	machine for running automated tests, called aambox6502. Also included
	is an emulator for this machine, built around a public domain 6502
	emulator called "fake6502" by Mike Chambers.

	A tool, aambundle, can convert an .aastory file into a web-friendly
	directory structure, including story and interpreter, ready for
	deployment on a server. The same tool can create disk images for the
	Commodore 64.

Directory structure:

	readme.txt	This file.
	license.txt	License and disclaimer.
	src		Source code for the Å-machine tools and interpreters.
	prebuilt	Binaries for Linux (i386, x86_64) and Windows.
	docs		The Å-machine specification.
	example		An example story in .aastory format, with interpreters.

To run the example story using Node.js:

	node src/js/nodefrontend.js example/cloak_rel2.aastory

To run the example story in a web browser, visit example/web/play.html.

To run the example story using the Vice Commodore 64 emulator, available at
<https://vice-emu.sourceforge.net/>:

	x64sc -truedrive -drivesound -reu -reusize 256 example/cloak-rel2.d64

To run on a real Commodore 64, insert the disk and type: LOAD"*",8
Then type: RUN

To build the Å-machine tools under Linux (requires a C compiler and make):

	cd src
	make

	(this will produce two executable files called aamshow and aambundle)

To cross-compile the Windows version of the Å-machine tools under Linux
(requires mingw32):

	cd src
	make aamshow.exe aambundle.exe

Note that when aambundle is built, several files are copied from src/js and
src/6502 into the resulting executable file. To rebuild the binary files in
src/6502, run "make" in that directory. This requires the xa65 assembler.

Project website:

	https://linusakesson.net/dialog/aamachine/

Release notes:

	0.4.1:

		Specification (and engines): Support for hyperlinks where the
		target text is determined from the displayed text.

		Specification (and engines): Clear Links opcode to transform
		old hyperlinks into plain text.

		Specification (and engines): Spans, i.e. inline text segments
		with style attributes.

		Specification (and engines): New runtime error: Invalid output
		state.
		
		Specification (and engines): Ability to check whether a value
		is a dictionary word that doesn't appear in the game dictionary
		(i.e. is represented internally by a list of characters).

		Specification (and engines): Ability to split and join
		dictionary words.

		Specification (and engines): Inhibit whitespace around certain
		stop characters when they are printed as a value.

		Specification (and engines): Several new opcodes and opcode
		variants to reduce bytecode footprint.

		Specification (and engines): Better text string encoding.

		Specification: Several improvements and clarifications,
		including an attempt at formalizing the output model.

		Javascript engine: Now handles extremely long input lines
		gracefully.

	0.3.1:

		Specification: Fixed several errors. Refer to the specification
		document for a detailed list.

		6502 engine: First release. Includes frontends for the
		Commodore 64 and the imaginary computer aambox6502 (for
		automated testing).

		aamshow: Rudimentary support for inspecting savefiles.

		Javascript engine: Fixed a case of heap corruption when
		attempting to unify a variable with itself.

		Javascript engine: Fixed a bug where the last two bytes of game
		state weren't included in the savefile.

		Javascript engine: No longer creates unnecessary trail entries
		during make_pair.

		Javascript engine: Allow resetting flags and clearing fields of
		non-null non-objects (nothing happens).

		Web interpreter: "Always re-focus" configuration option.

		Web interpreter: The link in the about box works now.

	0.2.2:

		Bugfix in the javascript engine: External restart (e.g. via the
		menu in the web interpreter) didn't work properly.

	0.2.1:

		Specification: Support for external resources (embedded and
		as link targets).

		Specification: Ability to check at runtime whether the
		interpreter supports quitting.

		Web interpreter: Support for embedded images, downloadable
		feelies, and external links.

		Web interpreter: Added “restart” and “save story file” menu
		items.

		Web interpreter: Don't automatically focus on the input element
		if the last command was clicked. Only do it if the last command
		was typed.

		Node.js frontend: Slight modification to the word-wrapping
		code, to ensure compatibility with dgdebug and dumbfrotz.

	0.1.2 (formerly known as 0.2):

		Engine bugfix: Runtime error handler can use undo.

		Web frontend: Improved CSS for progress bar.

		Web frontend: Improved screen reader support.

		Web frontend: Now possible to save gamestate and transcript in
		Internet Explorer.

		Web frontend: Added support for logging to a remote server.

		Web frontend: Text selection now works, for copy-paste.

		Web frontend: Simplified the HTML wrapper by moving most of the
		initial document structure to javascript.

	0.1.1 (formerly known as 0.1):

		First public release of the Å-machine tools, specifications,
		and official javascript interpreter.
