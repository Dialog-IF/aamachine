
#if (defined(_WIN32) || defined(__WIN32__))
#define mkdir(Path, Mode) mkdir(Path)
#endif

typedef void (*chunk_visitor_t)(char *head, char *dirname, uint8_t *chunk, uint32_t size);

extern uint8_t *story;
extern uint32_t storysize;

void visit_chunks(char *storyname, int storynamesize, chunk_visitor_t chunk_visitor);
void trim_chunks(int align_writ);

uint8_t *unicode_to_utf8(const uint32_t unichar);
void warn_about_nonascii(uint8_t *dict, uint32_t dictsize, uint8_t *lang, uint32_t langsize);

void bundle_web(char *dirname);
void bundle_c64(char *dirname);
void bundle_apple2(char *dirname);
void bundle_web_story(char *filename);
