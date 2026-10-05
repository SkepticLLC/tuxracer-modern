#ifndef MODERN_TEXT_H
#define MODERN_TEXT_H
#ifdef __cplusplus
extern "C" {
#endif
void modern_text_draw(const char *text, float x, float y, float size,
                      float r, float g, float b, float a, int weight);
void modern_text_clear_cache(void);
#ifdef __cplusplus
}
#endif
#endif
