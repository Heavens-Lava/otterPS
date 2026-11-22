export interface PaletteCommand {
  id: string;
  label: string;
  shortcut: string;
  command: string;
}

export function filterCommands(commands: PaletteCommand[], query: string): PaletteCommand[] {
  const q = query.trim().toLowerCase();
  if (!q) return commands;
  return commands.filter(
    (item) =>
      item.label.toLowerCase().includes(q) ||
      item.command.toLowerCase().includes(q)
  );
}
