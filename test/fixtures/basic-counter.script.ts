export interface Props {
  title: string;
  initialCount?: number;
}

export let props: Props;

let count = props.initialCount ?? 0;
const limit = 10;

function doubled() {
  return count * 2;
}

function increment() {
  count += 1;
}
