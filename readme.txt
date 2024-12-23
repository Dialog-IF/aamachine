This textfile uses UTF-8 encoding.

This archive contains version 0.2 of the Å-machine specification, and version
0.2.1 of the tools and official javascript interpreter.

Version number:

	The version number has three parts:

	* The first part changes when there are compatibility-breaking changes
	to the specification.

	* The second part changes when there are backwards-compatible changes
	to the specification (i.e. a 0.2 interpreter must be able to run any
	0.1 story).

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
	look better on the web, and are smaller and potentially faster on
	vintage hardware (the latter claim is unsubstantiated at the moment,
	but it has been an important design principle).

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

	Currently, only a single Å-machine interpreter exists. It is
	implemented in pure javascript, and must be combined with a frontend
	that handles all input and output. Two frontends are provided: A web
	frontend based on jquery, for publishing stories online, and a Node.js
	frontend for running automated tests. A tool, aambundle, can convert an
	.aastory file into a web-friendly directory structure, including story
	and interpreter, ready for deployment on a server.

Directory structure:

	readme.txt	This file.
	license.txt	License and disclaimer.
	src		Source code for the Å-machine tools and interpreter.
	prebuilt	Binaries for Linux (i386, x86_64) and Windows.
	docs		The Aa-machine specification.
	example		An example story in .aastory format, with a web player.

To run the example story using Node.js:

	node src/js/nodefrontend.js example/cloak_rel2.aastory

To run the example story in a web browser, visit example/cloak_rel2/play.html.

To build the software under Linux (requires a C compiler and make):

	cd src
	make

	(this will produce two executable files called aamshow and aambundle)

To cross-compile the Windows version of the software under Linux (requires
mingw32):

	cd src
	make aamshow.exe aambundle.exe

Project website:

	https://linusakesson.net/dialog/aamachine

Release notes:

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
