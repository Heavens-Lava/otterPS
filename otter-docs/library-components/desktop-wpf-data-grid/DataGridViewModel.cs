using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Data;

namespace OtterLibrary.Controls;

public sealed record GridRecord(string Name, string Category, string Status, string Version);

public sealed class DataGridViewModel : INotifyPropertyChanged
{
    private string _filterQuery = string.Empty;

    public ObservableCollection<GridRecord> Items { get; }
    public ICollectionView ItemsView { get; }

    public DataGridViewModel(IEnumerable<GridRecord> initialItems)
    {
        Items = new ObservableCollection<GridRecord>(initialItems);
        ItemsView = CollectionViewSource.GetDefaultView(Items);
        ItemsView.Filter = MatchesFilter;
    }

    public string FilterQuery
    {
        get => _filterQuery;
        set
        {
            if (_filterQuery == value) return;
            _filterQuery = value;
            OnPropertyChanged();
            ItemsView.Refresh();
            OnPropertyChanged(nameof(FilteredCountText));
        }
    }

    public string FilteredCountText => $"{ItemsView.Cast<object>().Count()} of {Items.Count} shown";

    private bool MatchesFilter(object obj)
    {
        if (obj is not GridRecord rec) return false;
        if (string.IsNullOrWhiteSpace(_filterQuery)) return true;
        return rec.Name.Contains(_filterQuery, StringComparison.OrdinalIgnoreCase)
            || rec.Category.Contains(_filterQuery, StringComparison.OrdinalIgnoreCase)
            || rec.Status.Contains(_filterQuery, StringComparison.OrdinalIgnoreCase);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
