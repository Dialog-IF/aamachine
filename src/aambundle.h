
#if (defined(_WIN32) || defined(__WIN32__))
#define mkdir(Path, Mode) mkdir(Path)
#endif

typedef void (*file_visitor_t)(char *dirname, uint8_t *chunk, uint32_t size);

extern uint8_t *story;
extern uint32_t storysize;

void visit_chunks(char *storyname, int storynamesize, file_visitor_t file_visitor);
void trim_chunks(int align_writ);

void bundle_web(char *dirname);
void bundle_c64(char *dirname);
