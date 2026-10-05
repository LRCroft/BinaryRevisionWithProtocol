import re

with open('docs.html', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove duplicate doc-streaming (the orphaned one after brp-43)
content = re.sub(
    r'</section>\s*<div class="container doc">\s*<p class="eyebrow">28 &middot; Streaming & Text/Binary</p>\s*<h2 id="doc-streaming-title">Streaming and Text/Binary Content <span class="spec-tag">Specification</span></h2>\s*<p>Protocol requirement: content is raw bytes, period\. Content-touching operations SHOULD support streaming so correctness never depends on loading an entire file into memory; exact streaming APIs stay language-idiomatic and unfrozen\. UTF-8 validity alone never classifies content as text, invalid UTF-8 is valid binary, binary data MUST NOT be modified, text diff is optional, hashes run on raw bytes, and byte identity outranks textual interpretation\. Newline normalization MUST NOT be part of the protocol\.</p>\s*<p><a href="#top">Back to top</a></p>\s*</div>\s*</section>\s*',
    '</section>',
    content,
    flags=re.DOTALL
)

# Remove doc-paths (we have brp-30, brp-31)
content = re.sub(
    r'<section class="section" id="doc-paths" aria-labelledby="doc-paths-title">.*?</section>\s*',
    '',
    content,
    flags=re.DOTALL
)

# Remove doc-restoretable (we have brp-22)
content = re.sub(
    r'<section class="section" id="doc-restoretable" aria-labelledby="doc-restoretable-title">.*?</section>\s*',
    '',
    content,
    flags=re.DOTALL
)

# Remove doc-interop (we have brp-43)
content = re.sub(
    r'<section class="section" id="doc-interop" aria-labelledby="doc-interop-title">.*?</section>\s*',
    '',
    content,
    flags=re.DOTALL
)

# Remove doc-retention (we have brp-39)
content = re.sub(
    r'<section class="section" id="doc-retention" aria-labelledby="doc-retention-title">.*?</section>\s*',
    '',
    content,
    flags=re.DOTALL
)

# Remove doc-freeze
content = re.sub(
    r'<section class="section" id="doc-freeze" aria-labelledby="doc-freeze-title">.*?</section>\s*',
    '',
    content,
    flags=re.DOTALL
)

# Remove doc-glossary
content = re.sub(
    r'<section class="section" id="doc-glossary" aria-labelledby="doc-glossary-title">.*?</section>\s*',
    '',
    content,
    flags=re.DOTALL
)

# Clean up multiple blank lines
content = re.sub(r'\n{4,}', '\n\n\n', content)

with open('docs.html', 'w', encoding='utf-8') as f:
    f.write(content)

print('Cleanup done')