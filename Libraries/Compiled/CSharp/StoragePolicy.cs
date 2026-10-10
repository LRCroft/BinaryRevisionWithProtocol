namespace Vsn;

/// <summary>Writer-side storage-policy profile (authoritative classification).</summary>
public enum StoragePolicy : int
{
    HIGHLY_VERTICAL = 1,
    VERTICAL = 2,
    HORIZONTAL = 3,
    HIGHLY_HORIZONTAL = 4,
}

/// <summary>Mapping from StoragePolicy to the normative wire ModeDeclaration.</summary>
public enum WireMode : byte
{
    MODERN = 0x01,
    ENTERPRISE = 0x02,
}

/// <summary>Canonical policy-to-wire-mode mapping (frozen contract).</summary>
public static class StoragePolicyMapping
{
    public static readonly System.Collections.Generic.Dictionary<StoragePolicy, byte> ToWireMode = new()
    {
        { StoragePolicy.HIGHLY_VERTICAL,   0x01 },
        { StoragePolicy.VERTICAL,         0x01 },
        { StoragePolicy.HORIZONTAL,       0x02 },
        { StoragePolicy.HIGHLY_HORIZONTAL, 0x02 },
    };

    public static byte Resolve(StoragePolicy p) => ToWireMode[p];
}

public class InvalidStoragePolicy : System.Exception { public InvalidStoragePolicy(int value) : base($"invalid storage policy: {value}") {} }
public class PolicyWireModeConflict : System.Exception { public PolicyWireModeConflict(StoragePolicy policy, byte constraint) : base($"policy {policy} conflicts with wire mode {constraint}") {} }
public class InvalidOptimizationConfiguration : System.Exception { public InvalidOptimizationConfiguration(string field, int value) : base($"invalid config: {field}={value}") {} }

/// <summary>Optional resource-budget parameters for StoragePolicy implementation.</summary>
public sealed class OptimizationConfiguration
{
    public int? SearchBudget { get; }
    public int? MemoryLimit { get; }
    public int? MaxDependencyDepth { get; }
    public int? MaxExtentCount { get; }
    public int? DecodeWorkLimit { get; }

    public OptimizationConfiguration(int? searchBudget = null, int? memoryLimit = null,
        int? maxDependencyDepth = null, int? maxExtentCount = null, int? decodeWorkLimit = null)
    {
        SearchBudget = searchBudget; MemoryLimit = memoryLimit;
        MaxDependencyDepth = maxDependencyDepth; MaxExtentCount = maxExtentCount;
        DecodeWorkLimit = decodeWorkLimit;
    }

    public void Validate()
    {
        if (SearchBudget.HasValue && SearchBudget.Value <= 0)
            throw new InvalidOptimizationConfiguration("search_budget", SearchBudget.Value);
        if (MemoryLimit.HasValue && MemoryLimit.Value <= 0)
            throw new InvalidOptimizationConfiguration("memory_limit", MemoryLimit.Value);
        if (MaxDependencyDepth.HasValue && MaxDependencyDepth.Value < 1)
            throw new InvalidOptimizationConfiguration("max_dependency_depth", MaxDependencyDepth.Value);
    }
}

/// <summary>Composition model for writer-side options per the Library API Contract.</summary>
public sealed class WriterOptions
{
    public StoragePolicy? StoragePolicy { get; }
    public byte? WireModeConstraint { get; }
    public OptimizationConfiguration? OptimizationConfig { get; }

    public WriterOptions(StoragePolicy? storagePolicy = null, byte? wireModeConstraint = null,
        OptimizationConfiguration? optimizationConfig = null)
    {
        StoragePolicy = storagePolicy; WireModeConstraint = wireModeConstraint;
        OptimizationConfig = optimizationConfig;
    }

    public byte? EffectiveWireMode => ResolveEffective();

    private byte? ResolveEffective()
    {
        var policy = StoragePolicy;
        var constraint = WireModeConstraint;
        if (policy == null && constraint == null) return null;
        if (policy != null && constraint != null)
        {
            var expected = StoragePolicyMapping.Resolve(policy.Value);
            if (constraint.Value != expected) throw new PolicyWireModeConflict(policy.Value, constraint.Value);
            return expected;
        }
        if (policy != null) return StoragePolicyMapping.Resolve(policy.Value);
        return constraint;
    }

    public int ResolveWireMode(int defaultMode) => EffectiveWireMode ?? defaultMode;

    public void Validate()
    {
        if (StoragePolicy.HasValue && (((int)StoragePolicy.Value) < 1 || ((int)StoragePolicy.Value) > 4))
            throw new InvalidStoragePolicy((int)StoragePolicy.Value);
        OptimizationConfig?.Validate();
    }
}