m4_define(`_VOID',void)m4_dnl
m4_define(`_CONST',const)m4_dnl
m4_define(`_PTR',void *)m4_dnl
m4_define(`_EXFUN',$1 $2)m4_dnl
m4_define(`_EXPARM',`('* $1`)' $2)m4_dnl
m4_define(`_PARAMS',$1)m4_dnl
m4_define(`__IMPORT',)m4_dnl
m4_define(`_READ_WRITE_RETURN_TYPE',_ssize_t)m4_dnl
m4_define(`_BEGIN_STD_C',`#'ifdef __cplusplus
extern "C" {
`#'endif)m4_dnl
m4_define(`_END_STD_C',`#'ifdef __cplusplus
}
`#'endif)m4_dnl
m4_define(`__BEGIN_DECLS',`#'ifdef __cplusplus
extern "C" {
`#'endif)m4_dnl
m4_define(`__END_DECLS',`#'ifdef __cplusplus
}
`#'endif)m4_dnl
m4_changequote(<!!!!!,!!!!!>)m4_dnl
m4_include(M4_FILE)m4_dnl
