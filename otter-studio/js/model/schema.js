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
    // hideheader, maxwidth, description and icon apply to a page (`app is a page`).
    allowedProperties: ['title', 'description', 'icon', 'width', 'height', 'maxwidth', 'hideheader', 'background', 'foreground', 'padding', 'spacing'],
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
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'spread', 'wrap', 'align', 'radius', 'round', 'opacity'],
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

  // A column that checks its fields when it is sent: a button in it, or Enter
  // in one of its text boxes (docs/proposals/FORMS_AND_VALIDATION.md).
  'form': {
    kind: 'form',
    label: 'Form',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="7" y1="8" x2="17" y2="8"/><line x1="7" y1="12" x2="17" y2="12"/><rect x="7" y="15.5" width="6" height="2.5" rx="1"/></svg>`,
    defaultProperties: {
      width: 'full',
      spacing: 12
    },
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'spread', 'align', 'radius', 'round', 'opacity'],
    events: ['sent']
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
    allowedProperties: ['text', 'placeholder', 'label', 'required', 'format', 'minlength', 'maxlength', 'minimum', 'maximum', 'message', 'width', 'height', 'background', 'foreground', 'radius', 'round', 'align', 'opacity', 'enabled'],
    events: ['changed', 'clicked']
  },

  'checkbox': {
    kind: 'checkbox',
    label: 'Checkbox',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>`,
    // Unticked: a box someone must tick (I agree) never starts ticked.
    defaultProperties: {
      text: 'Enable notification alerts',
      checked: false,
      foreground: '#cbd5e1'
    },
    allowedProperties: ['text', 'checked', 'label', 'required', 'message', 'foreground', 'enabled', 'opacity'],
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
    allowedProperties: ['placeholder', 'options', 'label', 'required', 'message', 'width', 'height', 'background', 'foreground', 'radius', 'round', 'enabled', 'opacity'],
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
  },

  // --- For websites and forms (the compiler's `link`, `text area`, ...) ------
  'link': {
    kind: 'link',
    label: 'Link',
    category: ComponentCategories.NAVIGATION,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/></svg>`,
    // A page anchor ("#features"), a path ("about.html") or a web address.
    defaultProperties: { text: 'Link', url: '#' },
    allowedProperties: ['text', 'url', 'size', 'foreground', 'weight', 'opacity'],
    events: ['clicked']
  },
  'text area': {
    kind: 'text area',
    label: 'Text Area',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9h10M7 13h10M7 17h6"/></svg>`,
    // The same colours as a text box, so a light page gets light ones.
    defaultProperties: { placeholder: 'Write a message...', rows: 4, width: 'full', background: '#1e293b', foreground: '#f8fafc', radius: 6 },
    allowedProperties: ['placeholder', 'text', 'rows', 'label', 'required', 'minlength', 'maxlength', 'message', 'width', 'height', 'background', 'foreground', 'radius', 'opacity'],
    events: ['changed']
  },
  'toggle': {
    kind: 'toggle',
    label: 'Toggle',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="7" width="20" height="10" rx="5"/><circle cx="16" cy="12" r="3"/></svg>`,
    defaultProperties: { text: 'Turn on', checked: false },
    allowedProperties: ['text', 'checked', 'foreground', 'opacity'],
    events: ['changed']
  },
  'radio': {
    kind: 'radio',
    label: 'Radio Button',
    category: ComponentCategories.INPUTS,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3" fill="currentColor"/></svg>`,
    // Radio buttons with the same group are one choice.
    defaultProperties: { text: 'Option', group: 'choice', checked: false },
    allowedProperties: ['text', 'group', 'checked', 'foreground', 'opacity'],
    events: ['changed']
  },
  'badge': {
    kind: 'badge',
    label: 'Badge',
    category: ComponentCategories.TYPOGRAPHY,
    isContainer: false,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="8" width="18" height="8" rx="4"/></svg>`,
    defaultProperties: { text: 'New' },
    allowedProperties: ['text', 'size', 'foreground', 'background', 'weight', 'radius', 'opacity'],
    events: []
  },
  'panel': {
    kind: 'panel',
    label: 'Panel',
    category: ComponentCategories.CONTAINERS,
    isContainer: true,
    icon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="16" rx="1"/></svg>`,
    defaultProperties: { width: 'full', spacing: 12, padding: 16 },
    allowedProperties: ['width', 'height', 'background', 'spacing', 'padding', 'align', 'radius', 'round', 'opacity'],
    events: []
  },

  // Kinds the compiler has but the designer cannot edit yet: shown (with the
  // real render's look) and selectable, never dropped; edited in code.
  'list': { kind: 'list', label: 'List', category: ComponentCategories.CONTROLS, isContainer: false, codeOnly: true, defaultProperties: {}, allowedProperties: ['width', 'height', 'opacity'], events: ['changed'] },
  'table': { kind: 'table', label: 'Table', category: ComponentCategories.CONTROLS, isContainer: false, codeOnly: true, defaultProperties: {}, allowedProperties: ['width', 'height', 'opacity'], events: [] },
  'canvas': { kind: 'canvas', label: 'Canvas', category: ComponentCategories.CONTROLS, isContainer: false, codeOnly: true, defaultProperties: {}, allowedProperties: ['width', 'height', 'opacity'], events: [] },
  'dialog': { kind: 'dialog', label: 'Dialog', category: ComponentCategories.CONTAINERS, isContainer: true, codeOnly: true, defaultProperties: {}, allowedProperties: ['width', 'height', 'opacity'], events: [] }
};

// Other spellings the compiler accepts for the same kinds.
export const KindAliases = {
  'page': 'window',
  'check box': 'checkbox',
  'drop down': 'dropdown',
  'select': 'dropdown',
  'range': 'slider',
  'progress': 'progress bar',
  'textarea': 'text area',
  'switch': 'toggle',
  'radio button': 'radio',
  'tag': 'badge',
  'modal': 'dialog'
};
