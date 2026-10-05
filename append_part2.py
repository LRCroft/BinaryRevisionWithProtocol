with open('part2.html', 'a', encoding='utf-8') as f:
    f.write('''
    <section class="section" id="brp-49" aria-labelledby="brp-49-title">
      <div class="container doc">
        <p class="eyebrow">49 &middot; Reference Algorithms</p>
        <h2 id="brp-49-title">Reference Algorithms <span class="spec-tag">Informative</span></h2>
        <p>Pseudocode: ComputeContentHash, CanonicalEncode, ComputeMembersDigest, CreateRevision, RestoreRevision, AcceptRevisionSet, VerifyVsn, RecoverVsn, CheckExpectedHead, ApplyIdempotentOperation, ReachabilityAnalysis. Language-neutral.</p>
        <p><a href="#top">Back to top</a></p>
      </div>
    </section>
    <section class="section" id="brp-50" aria-labelledby="brp-50-title">
      <div class="container doc">
        <p class="eyebrow">50 &middot; Examples</p>
        <h2 id="brp-50-title">Examples <span class="spec-tag">Informative</span></h2>
        <p>Examples informative only. Canonical RCMP-1 bytes and SHA-256 for illustration. Actual values from implementation and conformance vectors.</p>
        <p><a href="#top">Back to top</a></p>
      </div>
    </section>
    <section class="section" id="brp-51" aria-labelledby="brp-51-title">
      <div class="container doc">
        <p class="eyebrow">51 &middot; Glossary</p>
        <h2 id="brp-51-title">Glossary</h2>
        <dl class="grid concepts-grid">
          <div><dt>File</dt><dd>Physical bytes in a workspace.</dd></div>
          <div><dt>Logical File</dt><dd>Identity tracked by FileId across renames/moves.</dd></div>
          <div><dt>FileId</dt><dd>Authoritative identity of a logical file (UUID).</dd></div>
          <div><dt>Revision</dt><dd>One immutable state of one logical file.</dd></div>
          <div><dt>RevisionId</dt><dd>Stable identifier of a Revision.</dd></div>
          <div><dt>RevisionSet</dt><dd>Logical transaction grouping revisions for review/acceptance.</dd></div>
          <div><dt>RevisionSetId</dt><dd>Stable identifier of a RevisionSet.</dd></div>
          <div><dt>FileHead</dt><dd>Pointer to currently accepted revision.</dd></div>
          <div><dt>ContentRef</dt><dd>Stable reference to content bytes by hash/size (sha256:<64 hex>).</dd></div>
          <div><dt>ObjectRef</dt><dd>Reference to stored content object.</dd></div>
          <div><dt>DiffArtifact</dt><dd>Derived comparison between revisions.</dd></div>
          <div><dt>ApplyTransaction</dt><dd>Physical projection and recovery transaction.</dd></div>
          <div><dt>Logical Commit</dt><dd>Acceptance of reviewed RevisionSet.</dd></div>
          <div><dt>Workspace Projection</dt><dd>Materialized files from accepted state.</dd></div>
          <div><dt>.vsn</dt><dd>Self-contained file-local companion sidecar for revision data.</dd></div>
          <div><dt>VSN-1</dt><dd>Self-contained container format for BRP revision data.</dd></div>
          <div><dt>RCMP-1</dt><dd>Canonical binary encoding for BRP.</dd></div>
          <div><dt>MembersDigest</dt><dd>SHA-256 of canonically encoded RevisionSet members.</dd></div>
          <div><dt>Generation</dt><dd>Monotonic counter for atomic container writes.</dd></div>
          <div><dt>CommitMarker</dt><dd>Record indicating accepted state boundary.</dd></div>
        </dl>
        <p><a href="#top">Back to top</a></p>
      </div>
    </section>
''')
    print('Part 2 appended - part 1')