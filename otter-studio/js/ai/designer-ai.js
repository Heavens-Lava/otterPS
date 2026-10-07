/**
 * Otter Studio Visual Designer AI Planner & Executor
 * Converts natural-language UI descriptions into structured, inspectable Designer operations.
 * Enforces atomic transaction rollback if any step fails.
 */

export class DesignerAiPlanner {
  static normalizeKind(kind) {
    const k = (kind || '').toLowerCase();
    if (k === 'textinput' || k === 'input' || k === 'label') return 'text';
    if (k === 'card' || k === 'column' || k === 'row' || k === 'button' || k === 'checkbox' || k === 'grid' || k === 'window' || k === 'heading') {
      return k;
    }
    return 'text';
  }

  static planFromPrompt(prompt) {
    const p = (prompt || '').toLowerCase();
    const ops = [];

    if (p.includes('settings') || p.includes('preferences') || p.includes('profile')) {
      ops.push(
        { op: 'create-container', type: 'card', id: 'settingsCard', properties: { width: 440, height: 360, padding: 16, background: '#1e293b' } },
        { op: 'create-container', type: 'column', id: 'settingsCol', parentId: 'settingsCard', properties: { spacing: 10 } },
        { op: 'create-control', type: 'heading', id: 'titleHeading', parentId: 'settingsCol', properties: { text: 'Account Settings', level: 2 } },
        { op: 'create-control', type: 'text', id: 'nameLabel', parentId: 'settingsCol', properties: { text: 'Full Name' } },
        { op: 'create-control', type: 'text', id: 'nameInput', parentId: 'settingsCol', properties: { placeholder: 'Enter full name' } },
        { op: 'create-control', type: 'text', id: 'emailLabel', parentId: 'settingsCol', properties: { text: 'Email Address' } },
        { op: 'create-control', type: 'text', id: 'emailInput', parentId: 'settingsCol', properties: { placeholder: 'Enter email address' } }
      );

      if (p.includes('notification') || p.includes('notif') || p.includes('option')) {
        ops.push(
          { op: 'create-control', type: 'checkbox', id: 'emailNotifs', parentId: 'settingsCol', properties: { text: 'Enable email notifications', checked: true } }
        );
      }

      ops.push(
        { op: 'create-container', type: 'row', id: 'btnRow', parentId: 'settingsCol', properties: { spacing: 8 } },
        { op: 'create-control', type: 'button', id: 'cancelBtn', parentId: 'btnRow', properties: { text: 'Cancel', variant: 'secondary' } },
        { op: 'create-control', type: 'button', id: 'saveBtn', parentId: 'btnRow', properties: { text: 'Save', variant: 'primary' } }
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
   * Plans from prompt and executes transactionally on uiModel.
   * Returns a structured result with success flag and operations.
   */
  static planAndApply(prompt, uiModel) {
    try {
      const plan = this.planFromPrompt(prompt);
      const applyResult = this.applyPlan(plan, uiModel);
      return {
        success: true,
        operations: plan.operations,
        summary: plan.summary,
        createdCount: applyResult.createdCount,
        createdIds: applyResult.createdIds
      };
    } catch (err) {
      return {
        success: false,
        error: err.message,
        operations: []
      };
    }
  }

  /**
   * Applies raw operations transactionally to uiModel.
   * Returns a structured result { success, error } without throwing if used directly.
   */
  static applyOperations(operations, uiModel) {
    try {
      const result = this.applyPlan({ operations }, uiModel);
      return {
        success: true,
        operations,
        createdCount: result.createdCount,
        createdIds: result.createdIds
      };
    } catch (err) {
      return {
        success: false,
        error: err.message,
        operations
      };
    }
  }

  /**
   * Applies operations transactionally to uiModel.
   * If any operation fails, performs complete rollback to pre-transaction state.
   */
  static applyPlan(plan, uiModel) {
    if (!plan || !Array.isArray(plan.operations) || !uiModel) {
      throw new Error('Invalid plan or UI model');
    }

    let preTxSnapshot = null;
    if (typeof uiModel.serializeSnapshot === 'function') {
      preTxSnapshot = uiModel.serializeSnapshot();
    }

    if (typeof uiModel.saveSnapshot === 'function') {
      uiModel.saveSnapshot('AI Visual Designer Generation');
    }

    const createdIds = [];
    const nameToIdMap = new Map();

    try {
      for (let i = 0; i < plan.operations.length; i++) {
        const op = plan.operations[i];
        if (!op || !op.op) {
          throw new Error(`Operation at index ${i} is invalid or missing 'op' property`);
        }

        const normalizedKind = this.normalizeKind(op.type);
        switch (op.op) {
          case 'create-container':
          case 'create-control': {
            let targetParentId = uiModel.rootId;
            if (op.parentId) {
              if (uiModel.components && uiModel.components.has(op.parentId)) {
                targetParentId = op.parentId;
              } else if (typeof uiModel.findByName === 'function' && uiModel.findByName(op.parentId)) {
                targetParentId = uiModel.findByName(op.parentId).id;
              } else if (nameToIdMap.has(op.parentId)) {
                targetParentId = nameToIdMap.get(op.parentId);
              } else {
                throw new Error(`Target parent container '${op.parentId}' does not exist`);
              }
            }
            const comp = uiModel.createComponent(normalizedKind, {
              name: op.id,
              parentId: targetParentId,
              properties: op.properties || {}
            });
            if (comp) {
              createdIds.push(comp.id);
              nameToIdMap.set(op.id, comp.id);
              if (targetParentId && uiModel.components && uiModel.components.has(targetParentId)) {
                const parentComp = uiModel.components.get(targetParentId);
                if (parentComp && Array.isArray(parentComp.children) && !parentComp.children.includes(comp.id)) {
                  parentComp.children.push(comp.id);
                }
              }
            }
            break;
          }
          case 'set-property': {
            if (!uiModel.components.has(op.id)) {
              throw new Error(`Component '${op.id}' not found for property mutation`);
            }
            if (uiModel.setProperty) {
              uiModel.setProperty(op.id, op.property, op.value);
            }
            break;
          }
          case 'set-text': {
            if (!uiModel.components.has(op.id)) {
              throw new Error(`Component '${op.id}' not found for text mutation`);
            }
            if (uiModel.setProperty) {
              uiModel.setProperty(op.id, 'text', op.text);
            }
            break;
          }
          case 'reparent': {
            if (!uiModel.components.has(op.id) || !uiModel.components.has(op.newParentId)) {
              throw new Error(`Invalid source or target ID for reparent operation`);
            }
            if (uiModel.reparentComponent) {
              uiModel.reparentComponent(op.id, op.newParentId);
            }
            break;
          }
          default:
            throw new Error(`Unsupported Designer operation '${op.op}'`);
        }
      }

      if (createdIds.length > 0 && typeof uiModel.select === 'function') {
        uiModel.select(createdIds[0]);
      } else if (createdIds.length > 0 && typeof uiModel.selectComponent === 'function') {
        uiModel.selectComponent(createdIds[0]);
      }

      if (typeof uiModel.notify === 'function') {
        uiModel.notify();
      }

      return {
        success: true,
        createdCount: createdIds.length,
        createdIds
      };
    } catch (err) {
      // Roll back all changes completely
      if (preTxSnapshot && typeof uiModel.restoreSnapshot === 'function') {
        uiModel.restoreSnapshot(preTxSnapshot);
      }
      const txError = new Error(`Designer AI Transaction Failed: ${err.message}. All changes rolled back.`);
      txError.originalError = err;
      throw txError;
    }
  }
}
