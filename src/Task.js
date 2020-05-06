import React from 'react'
import Runs from './Runs';

class Task extends React.Component {
  render() {
    return (
      <li style={{
        color: (this.props.task.status.state === 'completed')
          ? 'green'
          : (this.props.task.status.state === 'failed')
            ? 'red'
            : 'black'
      }}>
        {this.props.task.task.metadata.name}
        <Runs runs={this.props.task.status.runs} />
      </li>
    );
  }
}

export default Task;
