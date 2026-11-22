using System.Windows.Controls;

namespace OtterLibrary.Controls;

public partial class FilterableDataGrid : UserControl
{
    public FilterableDataGrid()
    {
        InitializeComponent();
    }

    public void FocusFilter() => FilterBox.Focus();
}
