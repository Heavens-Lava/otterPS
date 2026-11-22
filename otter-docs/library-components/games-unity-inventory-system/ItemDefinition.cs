using UnityEngine;

namespace OtterLibrary.Inventory
{
    [CreateAssetMenu(menuName = "Otter Library/Item Definition")]
    public sealed class ItemDefinition : ScriptableObject
    {
        public string ItemId = "potion_health";
        public string DisplayName = "Health Potion";
        [Min(1)] public int MaxStack = 10;
    }
}
