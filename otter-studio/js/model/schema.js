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
      spread: false,
      align: 'middle'
    },
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'spread', 'align', 'radius', 'round', 'opacity'],
    events: []
  },

  'column': {
    kind: 'column',
    label: 'Column',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="5" width="18" height="14" rx="2"/><line x1="3" y1="10" x2="21" y2="10"/><line x1="3" y1="15" x2="21" y2="15"/></svg>`,
    defaultProperties: {
      // No padding or align here: the designer gives a new column inner
      // padding in the stylesheet, and a column's children fill its width
      // (sidebar navigation) unless the user aligns them.
      width: 'full',
      spacing: 8
    },
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'spread', 'align', 'radius', 'round', 'opacity'],
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
      spacing: 8
    },
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'radius', 'round', 'spread', 'align', 'opacity'],
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
      weight: 700
    },
    allowedProperties: ['text', 'size', 'foreground', 'background', 'weight', 'align', 'opacity'],
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
    allowedProperties: ['text', 'size', 'foreground', 'background', 'weight', 'align', 'opacity'],
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
      radius: 6,
      padding: 8
    },
    allowedProperties: ['text', 'width', 'height', 'background', 'foreground', 'radius', 'round', 'align', 'opacity', 'enabled'],
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
      radius: 6,
      padding: 8,
      weight: 700
    },
    allowedProperties: ['text', 'width', 'height', 'background', 'foreground', 'radius', 'round', 'align', 'opacity', 'enabled'],
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
      radius: 6,
      padding: 8
    },
    allowedProperties: ['text', 'width', 'height', 'background', 'foreground', 'radius', 'round', 'align', 'opacity', 'enabled'],
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
      radius: 6
    },
    allowedProperties: ['text', 'placeholder', 'width', 'height', 'background', 'foreground', 'radius', 'round', 'align', 'opacity', 'enabled'],
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
      radius: 6
    },
    allowedProperties: ['placeholder', 'width', 'height', 'background', 'foreground', 'radius', 'round', 'enabled', 'opacity'],
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
      radius: 4
    },
    allowedProperties: ['value', 'maximum', 'width', 'height', 'background', 'foreground', 'radius', 'round', 'opacity'],
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
      radius: 6
    },
    allowedProperties: ['source', 'width', 'height', 'radius', 'round', 'opacity'],
    events: ['clicked']
  }
};
