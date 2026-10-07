/**
 * Otter Studio Visual Designer AI Planner & Executor
 * Converts natural-language UI descriptions into structured, inspectable Designer operations.
 * Never generates opaque HTML or unmanaged CSS.
 */

export class DesignerAiPlanner {
  /**
   * Normalizes component kind to valid schema keys
   */
  static normalizeKind(kind) {
    const k = (kind || '').toLowerCase();
    if (k === 'textinput' || k === 'input' || k === 'label') return 'text';
    if (k === 'card' || k === 'column' || k === 'row' || k === 'button' || k === 'checkbox' || k === 'grid' || k === 'window' || k === 'heading') {
      return k;
    }
    return 'text';
  }

  /**
   * Plans structured operations from natural language prompts
   * @param {string} prompt
   * @returns {{ name: string, operations: Array<{ op: string, [key: string]: any }> }}
   */
  static planFromPrompt(prompt) {
    const p = (prompt || '').toLowerCase();
    const ops = [];

    if (p.includes('settings') || p.includes('preferences') || p.includes('profile')) {
      // Plan: Card -> Column -> Name Input -> Email Input -> Button Row (Cancel, Save)
      ops.push(
        { op: 'create-container', type: 'card', id: 'settingsCard', properties: { width: 420, height: 320, padding: 16, background: '#1e293b' } },
        { op: 'create-container', type: 'column', id: 'settingsCol', parentId: 'settingsCard', properties: { spacing: 10 } },
        { op: 'create-control', type: 'heading', id: 'titleHeading', parentId: 'settingsCol', properties: { text: 'Account Settings', level: 2 } },
        { op: 'create-control', type: 'text', id: 'nameLabel', parentId: 'settingsCol', properties: { text: 'Full Name' } },
        { op: 'create-control', type: 'text', id: 'nameInput', parentId: 'settingsCol', properties: { placeholder: 'Enter full name' } },
        { op: 'create-control', type: 'text', id: 'emailLabel', parentId: 'settingsCol', properties: { text: 'Email Address' } },
        { op: 'create-control', type: 'text', id: 'emailInput', parentId: 'settingsCol', properties: { placeholder: 'Enter email address' } },
        { op: 'create-container', type: 'row', id: 'btnRow', parentId: 'settingsCol', properties: { spacing: 8 } },
        { op: 'create-control', type: 'button', id: 'cancelBtn', parentId: 'btnRow', properties: { text: 'Cancel', variant: 'secondary' } },
        { op: 'create-control', type: 'button', id: 'saveBtn', parentId: 'btnRow', properties: { text: 'Save Settings', variant: 'primary' } }
      );
    } else if (p.includes('login') || p.includes('auth') || p.includes('sign in')) {
      ops.push(
        { op: 'create-container', type: 'card', id: 'loginCard', properties: { width: 360, height: 300, padding: 20 } },
        { op: 'create-container', type: 'column', id: 'loginCol', parentId: 'loginCard', properties: { spacing: 12 } },
        { op: 'create-control', type: 'heading', id: 'loginTitle', parentId: 'loginCol', properties: { text: 'Welcome Back', level: 2 } },
        { op: 'create-control', type: 'text', id: 'userInput', parentId: 'loginCol', properties: { placeholder: 'Username' } },
        { op: 'create-control', type: 'text', id: 'passInput', parentId: 'loginCol', properties: { placeholder: 'Password', isPassword: true } },
        { op: 'create-control', type: 'checkbox', id: 'rememberCheck', parentId: 'loginCol', properties: { text: 'Remember me', checked: true } },
        { op: 'create-control', type: 'button', id: 'submitBtn', parentId: 'loginCol', properties: { text: 'Sign In', variant: 'primary' } }
      );
    } else {
      ops.push(
        { op: 'create-container', type: 'card', id: 'mainCard', properties: { width: 340, height: 180, padding: 16 } },
        { op: 'create-container', type: 'column', id: 'cardCol', parentId: 'mainCard', properties: { spacing: 8 } },
        { op: 'create-control', type: 'heading', id: 'cardTitle', parentId: 'cardCol', properties: { text: 'Generated View', level: 3 } },
        { op: 'create-control', type: 'button', id: 'actionBtn', parentId: 'cardCol', properties: { text: 'Click Here', variant: 'primary' } }
      );
    }

    return {
      prompt,
      operations: ops,
      summary: `Generated ${ops.length} structured Designer operations.`
    };
  }

  /**
   * Applies the operations plan to the OtterUiModel as a single undoable transaction
   * @param {{ operations: Array<any> }} plan
   * @param {any} uiModel
   */
  static applyPlan(plan, uiModel) {
    if (!plan || !Array.isArray(plan.operations) || !uiModel) {
      throw new Error('Invalid plan or UI model');
    }

    if (typeof uiModel.saveSnapshot === 'function') {
      uiModel.saveSnapshot('AI Visual Designer Generation');
    }

    const createdIds = [];

    for (const op of plan.operations) {
      const normalizedKind = this.normalizeKind(op.type);
      switch (op.op) {
        case 'create-container':
        case 'create-control': {
          const comp = uiModel.createComponent(normalizedKind, {
            name: op.id,
            parentId: op.parentId || uiModel.rootId,
            properties: op.properties || {}
          });
          if (comp) createdIds.push(comp.id);
          break;
        }
        case 'set-property': {
          if (uiModel.setProperty) {
            uiModel.setProperty(op.id, op.property, op.value);
          }
          break;
        }
        case 'set-text': {
          if (uiModel.setProperty) {
            uiModel.setProperty(op.id, 'text', op.text);
          }
          break;
        }
        case 'reparent': {
          if (uiModel.reparentComponent) {
            uiModel.reparentComponent(op.id, op.newParentId);
          }
          break;
        }
      }
    }

    if (createdIds.length > 0 && typeof uiModel.selectComponent === 'function') {
      uiModel.selectComponent(createdIds[0]);
    }

    if (typeof uiModel.notifyListeners === 'function') {
      uiModel.notifyListeners();
    }

    return {
      success: true,
      createdCount: createdIds.length,
      createdIds
    };
  }
}
