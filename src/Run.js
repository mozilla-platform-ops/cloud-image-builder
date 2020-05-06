import React from 'react'

class Run extends React.Component {
  render() {
    return (
      <li style={{
        color: (this.props.run.state === 'completed')
          ? 'green'
          : (this.props.run.state === 'failed')
            ? 'red'
            : (this.props.run.state === 'exception')
              ? 'orange'
              : 'black'
      }}>
        {this.props.run.runId} {this.props.run.state}
      </li>
    );
  }
}

export default Run;
