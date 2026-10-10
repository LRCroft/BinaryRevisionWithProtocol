// VSN Library Constants for Objective-C
// Storage Policy values -- authoritative classification (directly on wire)

// Storage Policy record type and field ID (new)
static const short REC_STORAGE_POLICY = 0x0009;
static const short FID_STORAGE_POLICY   = 0x0901;

// Wire modes -- OBSOLETE: deprecated, kept for reader compatibility only
static const int MODE_MODERN        = 1;
static const int MODE_ENTERPRISE    = 2;

// Storage Policy profiles (authoritative, maps to wire mode)
static const int STORAGE_POLICY_HIGHLY_VERTICAL   = 1;
static const int STORAGE_POLICY_VERTICAL          = 2;
static const int STORAGE_POLICY_HORIZONTAL        = 3;
static const int STORAGE_POLICY_HIGHLY_HORIZONTAL = 4;

// Representations
static const int REP_DIRECT_1   = 1;
static const int REP_EXTENTS_1  = 2;

// Magic bytes and frame markers
static const char MAGIC[]    = "VSN-";
static const int CFV         = 1;
static const int EV          = 1;

// Error codes
static const int ERR_TRUNCATED      = 0x0002;
static const int ERR_UNKNOWN_FILE_ID = 0x0009;
static const int ERR_INVALID_CANONICAL_STATE = 0x000C;

// Encode container with Storage Policy record (returns NSData)
NSData* vsn_encode_with_policy(int mode, long long gen, int storagePolicy);

// Parse storage policy from canonical bytes (returns policy value or 0 if not found)
int vsn_parse_storage_policy(const void* data, int len);


