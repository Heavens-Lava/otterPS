using System;
using System.Collections.Generic;
using UnityEngine;

namespace OtterLibrary.Inventory
{
    [Serializable]
    public sealed class InventorySlot
    {
        public ItemDefinition Item;
        public int Quantity;
    }

    public sealed class InventoryContainer : MonoBehaviour
    {
        [Min(1)] [SerializeField] private int capacity = 16;
        private readonly List<InventorySlot> _slots = new();

        public event Action OnInventoryChanged;
        public IReadOnlyList<InventorySlot> Slots => _slots;
        public int Capacity => capacity;

        public bool TryAdd(ItemDefinition item, int quantity)
        {
            if (item == null || quantity <= 0) return false;

            int remaining = quantity;
            foreach (var slot in _slots)
            {
                if (slot.Item != item || slot.Quantity >= item.MaxStack) continue;
                int space = item.MaxStack - slot.Quantity;
                int toAdd = Math.Min(space, remaining);
                slot.Quantity += toAdd;
                remaining -= toAdd;
                if (remaining == 0) break;
            }

            while (remaining > 0 && _slots.Count < capacity)
            {
                int toAdd = Math.Min(item.MaxStack, remaining);
                _slots.Add(new InventorySlot { Item = item, Quantity = toAdd });
                remaining -= toAdd;
            }

            if (remaining < quantity) OnInventoryChanged?.Invoke();
            return remaining == 0;
        }

        public bool TryConsume(ItemDefinition item, int quantity)
        {
            if (item == null || quantity <= 0) return false;
            int available = 0;
            foreach (var slot in _slots) if (slot.Item == item) available += slot.Quantity;
            if (available < quantity) return false;

            int remaining = quantity;
            for (int i = _slots.Count - 1; i >= 0 && remaining > 0; i--)
            {
                if (_slots[i].Item != item) continue;
                int take = Math.Min(_slots[i].Quantity, remaining);
                _slots[i].Quantity -= take;
                remaining -= take;
                if (_slots[i].Quantity == 0) _slots.RemoveAt(i);
            }

            OnInventoryChanged?.Invoke();
            return true;
        }
    }
}
