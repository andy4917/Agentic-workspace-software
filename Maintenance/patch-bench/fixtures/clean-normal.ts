export function calculateNoticeCount(input: { rooms: string[]; branch: string }) {
  return input.rooms.filter((room) => room.length > 0 && input.branch.length > 0).length;
}
