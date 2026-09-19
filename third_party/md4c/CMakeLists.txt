# md4c — vendored CommonMark parser. See README.heap.md for provenance.
#
# Built as a static library so no new DLL enters the Windows portable bundle and
# no package has to be discovered on any platform.

add_library(heap_md4c STATIC md4c.c)

target_include_directories(heap_md4c SYSTEM PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# Qt links md4c too (QTextDocument::setMarkdown), as a shared library on some
# platforms. Hidden visibility keeps our copy from being exported, and renaming
# the entry point keeps our calls from binding to Qt's. Both are PUBLIC-facing
# via the macro so every translation unit that includes md4c.h agrees.
target_compile_definitions(heap_md4c PUBLIC md_parse=heap_md_parse)

set_target_properties(heap_md4c PROPERTIES
    C_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
    POSITION_INDEPENDENT_CODE ON
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)

# Third-party code is not held to this project's warning settings; upstream
# compiles clean on its own terms and we do not patch it.
if (MSVC)
    target_compile_options(heap_md4c PRIVATE /w)
else ()
    target_compile_options(heap_md4c PRIVATE -w)
endif ()
