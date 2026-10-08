#if (defined(_WIN32) || defined(__WIN32__))
#define mkdir(Path, Mode) mkdir(Path)
#endif

#include <stdarg.h>

typedef void (*chunk_visitor_t)(char *head, char *dirname, uint8_t *chunk, uint32_t size);

extern uint8_t *story;
extern uint32_t storysize;

void visit_chunks(char *storyname, int storynamesize, chunk_visitor_t chunk_visitor);

/* Locate a chunk in the story, returning its payload and (if sizep is
 * non-null) its size, or null if the story has no such chunk.
 *
 * The returned pointer is only valid until the next rewrite_chunks(), which
 * replaces the story buffer wholesale. */

uint8_t *find_chunk(const char *id, uint32_t *sizep);

/* Rewrite the story in a single pass. For every chunk, the rewriter says
 * whether to keep it as it is, drop it, or replace it -- in which case it
 * fills in newid (four characters, not terminated), newdata and newsize. A
 * replacement buffer must stay alive until rewrite_chunks() returns.
 *
 * A null rewriter keeps everything. */

typedef enum {
	CHUNK_KEEP,
	CHUNK_DROP,
	CHUNK_REPLACE,
	CHUNK_INSERT
} chunk_action_t;

typedef chunk_action_t (*chunk_rewriter_t)(
	const char *id,
	uint8_t *data,
	uint32_t size,
	char *newid,
	uint8_t **newdata,
	uint32_t *newsize);

void rewrite_chunks(chunk_rewriter_t rewriter, int align_writ);

/* Warnings, similar to how dialogc does them */

#define WARN_DEFAULT	0
#define WARN_ALWAYS	1
#define WARN_NEVER	2

extern int charset_warning_level;
extern int input_warning_level;
extern int style_warning_level;
extern int nwarning;

/* One entry per warning kind; warn_info[] in aambundle.c maps a
 * warn_id_t to the flag that disables it and to its level variable. */
typedef enum {
	WARN_ERROR,
	WARN_CHARSET,
	WARN_INPUT,
	WARN_STYLE,
	WARN_COUNT
} warn_id_t;

/* Print a warning. Unless the warning was forced on with --warn-<kind>,
 * a hint suggesting its disabling flag is printed after the message. */
void warning(warn_id_t id, const char *fmt, ...);
void vwarning(warn_id_t id, const char *fmt, va_list ap);

/* Style precomputation (USTY chunk), implemented in gen_usty.c. Call
 * gen_usty_set_target() before rewrite_chunks() on the 8-bit targets.
 */
void gen_usty_set_target(const char *target);

/* Call after rewrite_chunks() on a 6502 target: aborts if the interpreter
 * needs a USTY table and none was emitted.
 */
void gen_usty_check(void);

chunk_action_t rewrite_6502_sty(
	const char *id,
	uint8_t *data,
	uint32_t size,
	char *newid,
	uint8_t **newdata,
	uint32_t *newsize);

/* main bundle routines */

void writefile_padded(char *dirname, char *name, const uint8_t *data, size_t size, size_t padto);
void writefile(char *dirname, char *name, const uint8_t *data, size_t size);
	/* dirname may be NULL, meaning "relative to the current directory". */

uint8_t *unicode_to_utf8(const uint32_t unichar);
void warn_about_nonascii(uint8_t *dict, uint32_t dictsize, uint8_t *lang, uint32_t langsize);

void bundle_web(char *dirname);
void bundle_c64(char *dirname);
void bundle_apple2(char *dirname);
void bundle_web_story(char *filename);
void bundle_aambox(char *filename);
