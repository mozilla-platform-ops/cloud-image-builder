import React from 'react'
import Status from './Status';

class Statuses extends React.Component {
  state = {
    summary: {
      completed: 0,
      failed: 0,
      exception: 0,
      running: 0,
      pending: 0,
      unscheduled: 0
    }
  };

  constructor(props) {
    super(props);
    this.appendToSummary = this.appendToSummary.bind(this);
  }

  appendToSummary(summary) {
    this.setState(state => {
      let combined = {
        completed: state.summary.completed + summary.completed,
        failed: state.summary.failed + summary.failed,
        exception: state.summary.exception + summary.exception,
        running: state.summary.running + summary.running,
        pending: state.summary.pending + summary.pending,
        unscheduled: state.summary.unscheduled + summary.unscheduled
      };
      this.props.appender(combined);
      return { summary: combined };
    });
  }

  componentDidMount() {
    // mock:
    this.appendToSummary({
      completed: 3,
      failed: 0,
      exception: 2,
      running: 0,
      pending: 0,
      unscheduled: 0
    });
  }

  render() {
    return (
      <ul>
        {
          this.props.contexts.map((context, cI) => (
            <li key={cI}>
              { context }
              <ul>
              {
                // only show pending statuses if there are no others (eg: failed/completed)
                (this.props.statuses.some(s => s.context === context && s.state !== 'pending'))
                  ? this.props.statuses.filter(s => s.context === context && s.state !== 'pending').map((status) => (
                    <Status status={status} key={status.id} appender={this.appendToSummary} />
                  ))
                  : this.props.statuses.filter(s => s.context === context).map((status) => (
                    <Status status={status} key={status.id} appender={this.appendToSummary} />
                  ))
              }
              </ul>
            </li>
          ))
        }
      </ul>
    );
  }
}

export default Statuses;
