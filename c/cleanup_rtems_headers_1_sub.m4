m4_define(`__P',$1)m4_dnl
m4_define(`__BEGIN_DECLS',`#'ifdef __cplusplus
extern "C" {
`#'endif)m4_dnl
m4_define(`__END_DECLS',`#'ifdef __cplusplus
}
`#'endif)m4_dnl
m4_changequote(<!!!!!,!!!!!>)m4_dnl
m4_include(M4_FILE)m4_dnl
