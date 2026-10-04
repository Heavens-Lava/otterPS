// schema.js - Component definitions, default properties, and layout metadata

export const ComponentCategories = {
  CONTAINERS: 'Containers',
  CONTROLS: 'Controls',
  TYPOGRAPHY: 'Typography',
  INPUTS: 'Inputs',
  NAVIGATION: 'Navigation'
};

export const ComponentSchema = {
  'window': {
    kind: 'window',
    label: 'Window',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    isRoot: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="18" rx="2"/><line x1="2" y1="8" x2="22" y2="8"/><circle cx="6" cy="5.5" r="1" fill="currentColor"/><circle cx="9" cy="5.5" r="1" fill="currentColor"/><circle cx="12" cy="5.5" r="1" fill="currentColor"/></svg>`,
    defaultProperties: {
      title: 'New Application',
      width: 760,
      height: 540,
      background: '#0f172a',
      padding: 16,
      spacing: 12
    },
    allowedProperties: ['title', 'width', 'height', 'background', 'foreground', 'padding', 'spacing'],
    events: ['closed']
  },

  'row': {
    kind: 'row',
    label: 'Row',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="5" width="18" height="14" rx="2"/><line x1="9" y1="5" x2="9" y2="19"/><line x1="15" y1="5" x2="15" y2="19"/></svg>`,
    defaultProperties: {
      width: 'full',
      spacing: 10,
      padding: 0,
      spread: false,
      align: 'middle'
    },
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'spread', 'align', 'round', 'opacity'],
    events: []
  },

  'column': {
    kind: 'column',
    label: 'Column',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="5" width="18" height="14" rx="2"/><line x1="3" y1="10" x2="21" y2="10"/><line x1="3" y1="15" x2="21" y2="15"/></svg>`,
    defaultProperties: {
      width: 'full',
      spacing: 8,
      padding: 0,
      align: 'left'
    },
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'spread', 'align', 'round', 'opacity'],
    events: []
  },

  'card': {
    kind: 'card',
    label: 'Card',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="4"/><line x1="3" y1="9" x2="21" y2="9"/></svg>`,
    defaultProperties: {
      width: 'full',
      background: '#1e293b',
      padding: 16,
      spacing: 8,
      round: 8
    },
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'round', 'spread', 'align', 'opacity'],
    events: []
  },

  'scroll': {
    kind: 'scroll',
    label: 'Scroll Area',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    maxChildren: 1,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="19" y1="6" x2="19" y2="18"/><circle cx="19" cy="10" r="1" fill="currentColor"/></svg>`,
    defaultProperties: {
      width: 'full',
      height: 300,
      background: '#0f172a'
    },
    allowedProperties: ['width', 'height', 'background', 'opacity'],
    events: []
  },

  'grid': {
    kind: 'grid',
    label: 'Grid',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="12" y1="3" x2="12" y2="21"/><line x1="3" y1="12" x2="21" y2="12"/></svg>`,
    defaultProperties: {
      width: 'full',
      columns: 2,
      rows: 'auto',
      spacing: 12,
      padding: 0
    },
    allowedProperties: ['width', 'height', 'background', 'columns', 'rows', 'spacing', 'padding', 'round', 'opacity'],
    events: []
  },

  'heading': {
    kind: 'heading',
    label: 'Heading',
    category: ComponentCategories.TYPOGRAPHY,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 12h16"/><path d="M4 4v16"/><path d="M20 4v16"/></svg>`,
    defaultProperties: {
      text: 'Heading Title',
      size: 22,
      foreground: '#f8fafc',
      bold: true
    },
    allowedProperties: ['text', 'size', 'foreground', 'background', 'bold', 'align', 'opacity'],
    events: []
  },

  'text': {
    kind: 'text',
    label: 'Text Label',
    category: ComponentCategories.TYPOGRAPHY,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="4 7 4 4 20 4 20 7"/><line x1="9" y1="20" x2="15" y2="20"/><line x1="12" y1="4" x2="12" y2="20"/></svg>`,
    defaultProperties: {
      text: 'Informational text label',
      size: 14,
      foreground: '#cbd5e1'
    },
    allowedProperties: ['text', 'size', 'foreground', 'background', 'bold', 'align', 'opacity'],
    events: []
  },

  'button': {
    kind: 'button',
    label: 'Button',
    category: ComponentCategories.CONTROLS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="6" width="18" height="12" rx="3"/><line x1="8" y1="12" x2="16" y2="12"/></svg>`,
    defaultProperties: {
      text: 'Button',
      background: '#334155',
      foreground: '#ffffff',
      round: 6,
      padding: 8
    },
    allowedProperties: ['text', 'width', 'height', 'background', 'foreground', 'round', 'align', 'opacity', 'enabled'],
    events: ['clicked']
  },

  'primary button': {
    kind: 'primary button',
    label: 'Primary Button',
    category: ComponentCategories.CONTROLS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="6" width="18" height="12" rx="3" fill="#2563eb"/><line x1="8" y1="12" x2="16" y2="12" stroke="#fff"/></svg>`,
    defaultProperties: {
      text: 'Save Changes',
      background: '#2563eb',
      foreground: '#ffffff',
      round: 6,
      padding: 8,
      bold: true
    },
    allowedProperties: ['text', 'width', 'height', 'background', 'foreground', 'round', 'align', 'opacity', 'enabled'],
    events: ['clicked']
  },

  'danger button': {
    kind: 'danger button',
    label: 'Danger Button',
    category: ComponentCategories.CONTROLS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="6" width="18" height="12" rx="3" fill="#dc2626"/><line x1="8" y1="12" x2="16" y2="12" stroke="#fff"/></svg>`,
    defaultProperties: {
      text: 'Delete Item',
      background: '#dc2626',
      foreground: '#ffffff',
      round: 6,
      padding: 8
    },
    allowedProperties: ['text', 'width', 'height', 'background', 'foreground', 'round', 'align', 'opacity', 'enabled'],
    events: ['clicked']
  },

  'text box': {
    kind: 'text box',
    label: 'Text Box',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="6" width="20" height="12" rx="2"/><line x1="6" y1="12" x2="6.01" y2="12"/></svg>`,
    defaultProperties: {
      text: '',
      placeholder: 'Enter text...',
      width: 'full',
      height: 38,
      background: '#1e293b',
      foreground: '#f8fafc',
      round: 6
    },
    allowedProperties: ['text', 'placeholder', 'width', 'height', 'background', 'foreground', 'round', 'align', 'opacity', 'enabled'],
    events: ['changed', 'clicked']
  },

  'checkbox': {
    kind: 'checkbox',
    label: 'Checkbox',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>`,
    defaultProperties: {
      text: 'Enable notification alerts',
      checked: true,
      foreground: '#cbd5e1'
    },
    allowedProperties: ['text', 'checked', 'foreground', 'enabled', 'opacity'],
    events: ['changed']
  },

  'slider': {
    kind: 'slider',
    label: 'Slider',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="4" y1="12" x2="20" y2="12"/><circle cx="12" cy="12" r="3" fill="currentColor"/></svg>`,
    defaultProperties: {
      value: 50,
      minimum: 0,
      maximum: 100,
      width: 'full'
    },
    allowedProperties: ['value', 'minimum', 'maximum', 'width', 'enabled', 'opacity'],
    events: ['changed']
  },

  'dropdown': {
    kind: 'dropdown',
    label: 'Dropdown',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="5" width="18" height="14" rx="2"/><polyline points="8 10 12 14 16 10"/></svg>`,
    defaultProperties: {
      placeholder: 'Select option...',
      width: 'full',
      background: '#1e293b',
      foreground: '#f8fafc',
      round: 6
    },
    allowedProperties: ['placeholder', 'width', 'height', 'background', 'foreground', 'round', 'enabled', 'opacity'],
    events: ['changed']
  },

  'progress bar': {
    kind: 'progress bar',
    label: 'Progress Bar',
    category: ComponentCategories.CONTROLS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="8" width="20" height="8" rx="2"/><rect x="2" y="8" width="12" height="8" rx="2" fill="currentColor"/></svg>`,
    defaultProperties: {
      value: 65,
      maximum: 100,
      width: 'full',
      height: 10,
      background: '#1e293b',
      foreground: '#3b82f6',
      round: 4
    },
    allowedProperties: ['value', 'maximum', 'width', 'height', 'background', 'foreground', 'round', 'opacity'],
    events: []
  },

  'image': {
    kind: 'image',
    label: 'Image',
    category: ComponentCategories.CONTROLS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>`,
    defaultProperties: {
      source: 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=500&auto=format&fit=crop&q=60',
      width: 200,
      height: 140,
      round: 6
    },
    allowedProperties: ['source', 'width', 'height', 'round', 'opacity'],
    events: ['clicked']
  },

  'text area': {
    kind: 'text area',
    label: 'Text Area',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="7" y1="7" x2="17" y2="7"/><line x1="7" y1="12" x2="17" y2="12"/><line x1="7" y1="17" x2="13" y2="17"/></svg>`,
    defaultProperties: {
      text: '',
      placeholder: 'Enter multi-line text...',
      width: 'full',
      height: 100,
      background: '#1e293b',
      foreground: '#f8fafc',
      round: 6
    },
    allowedProperties: ['text', 'placeholder', 'width', 'height', 'background', 'foreground', 'round', 'enabled', 'opacity'],
    events: ['changed']
  },

  'radio': {
    kind: 'radio',
    label: 'Radio Button',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4" fill="currentColor"/></svg>`,
    defaultProperties: {
      text: 'Option Selection',
      checked: false,
      group: 'options',
      foreground: '#cbd5e1'
    },
    allowedProperties: ['text', 'checked', 'group', 'foreground', 'enabled', 'opacity'],
    events: ['changed', 'clicked']
  },

  'toggle': {
    kind: 'toggle',
    label: 'Toggle Switch',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="7" width="20" height="10" rx="5"/><circle cx="16" cy="12" r="3" fill="currentColor"/></svg>`,
    defaultProperties: {
      text: 'Toggle setting',
      checked: false,
      foreground: '#cbd5e1'
    },
    allowedProperties: ['text', 'checked', 'foreground', 'enabled', 'opacity'],
    events: ['changed']
  },

  'list': {
    kind: 'list',
    label: 'List',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>`,
    defaultProperties: {
      width: 'full',
      height: 180,
      background: '#1e293b',
      spacing: 4,
      padding: 8,
      round: 6
    },
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'round', 'opacity'],
    events: ['selected']
  },

  'table': {
    kind: 'table',
    label: 'Table / Data Grid',
    category: ComponentCategories.CONTAINERS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M3 15h18M9 3v18M15 3v18"/></svg>`,
    defaultProperties: {
      width: 'full',
      height: 220,
      background: '#1e293b',
      foreground: '#f8fafc',
      round: 6
    },
    allowedProperties: ['width', 'height', 'background', 'foreground', 'round', 'opacity'],
    events: ['selected']
  },

  'tree': {
    kind: 'tree',
    label: 'Tree View',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="6" height="6"/><rect x="15" y="7" width="6" height="6"/><rect x="15" y="15" width="6" height="6"/><path d="M6 9v9h9M6 10h9"/></svg>`,
    defaultProperties: {
      width: 'full',
      height: 200,
      background: '#1e293b',
      padding: 8
    },
    allowedProperties: ['width', 'height', 'background', 'padding', 'round', 'opacity'],
    events: ['selected']
  },

  'tabs': {
    kind: 'tabs',
    label: 'Tabs Container',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M2 9h20M2 4h6l2 3h12v13a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V4z"/></svg>`,
    defaultProperties: {
      width: 'full',
      activeTab: 0,
      background: '#1e293b',
      padding: 12
    },
    allowedProperties: ['width', 'height', 'background', 'padding', 'round', 'opacity'],
    events: ['changed']
  },

  'menu': {
    kind: 'menu',
    label: 'Menu Bar',
    category: ComponentCategories.NAVIGATION,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="18" x2="21" y2="18"/></svg>`,
    defaultProperties: {
      width: 'full',
      height: 32,
      background: '#1e293b',
      foreground: '#cbd5e1'
    },
    allowedProperties: ['width', 'height', 'background', 'foreground', 'opacity'],
    events: ['selected']
  },

  'toolbar': {
    kind: 'toolbar',
    label: 'Toolbar',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="5" width="20" height="14" rx="2"/><line x1="6" y1="9" x2="6" y2="15"/><line x1="10" y1="9" x2="10" y2="15"/><line x1="14" y1="9" x2="14" y2="15"/></svg>`,
    defaultProperties: {
      width: 'full',
      height: 42,
      background: '#1e293b',
      spacing: 8,
      padding: 6
    },
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'round', 'opacity'],
    events: []
  },

  'status bar': {
    kind: 'status bar',
    label: 'Status Bar',
    category: ComponentCategories.CONTAINERS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="16" width="20" height="6" rx="1"/><circle cx="5" cy="19" r="1" fill="#10b981"/></svg>`,
    defaultProperties: {
      text: 'Ready',
      width: 'full',
      height: 26,
      background: '#0f172a',
      foreground: '#94a3b8'
    },
    allowedProperties: ['text', 'width', 'height', 'background', 'foreground', 'opacity'],
    events: []
  },

  'dialog': {
    kind: 'dialog',
    label: 'Dialog / Modal',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="9" y1="9" x2="15" y2="15"/><line x1="15" y1="9" x2="9" y2="15"/></svg>`,
    defaultProperties: {
      title: 'Modal Dialog',
      width: 460,
      height: 280,
      background: '#1e293b',
      padding: 16,
      round: 8
    },
    allowedProperties: ['title', 'width', 'height', 'background', 'padding', 'round', 'opacity'],
    events: ['closed']
  },

  'icon': {
    kind: 'icon',
    label: 'Icon',
    category: ComponentCategories.CONTROLS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>`,
    defaultProperties: {
      name: 'star',
      size: 20,
      foreground: '#fbbf24'
    },
    allowedProperties: ['name', 'size', 'foreground', 'opacity'],
    events: ['clicked']
  },

  'date picker': {
    kind: 'date picker',
    label: 'Date Picker',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>`,
    defaultProperties: {
      value: '',
      width: 180,
      background: '#1e293b',
      foreground: '#f8fafc',
      round: 6
    },
    allowedProperties: ['value', 'width', 'background', 'foreground', 'round', 'enabled', 'opacity'],
    events: ['changed']
  },

  'split pane': {
    kind: 'split pane',
    label: 'Split Pane',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="12" y1="3" x2="12" y2="21"/></svg>`,
    defaultProperties: {
      width: 'full',
      height: 300,
      split: 50,
      background: '#0f172a'
    },
    allowedProperties: ['width', 'height', 'split', 'background', 'opacity'],
    events: []
  },

  'canvas': {
    kind: 'canvas',
    label: 'Canvas / Game Surface',
    category: ComponentCategories.CONTAINERS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>`,
    defaultProperties: {
      width: 400,
      height: 300,
      background: '#000000',
      round: 4
    },
    allowedProperties: ['width', 'height', 'background', 'round', 'opacity'],
    events: ['clicked']
  },

  'custom': {
    kind: 'custom',
    label: 'Custom Component',
    category: ComponentCategories.CONTROLS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 8v8M8 12h8"/></svg>`,
    defaultProperties: {
      tag: 'custom-view',
      width: 'full',
      padding: 12
    },
    allowedProperties: ['tag', 'width', 'height', 'background', 'padding', 'opacity'],
    events: ['clicked']
  }
};
