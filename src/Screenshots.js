import React from 'react';
import ImageGallery from 'react-image-gallery';
//import Screenshot from './Screenshot';

class Screenshots extends React.Component {
  state = {
    screenshots: [],
    thumbnailPosition: (window.innerWidth < 960) ? 'bottom' : 'left',
    galleryWidth: (window.innerWidth < 960) ? 640 : (640 + 48 + 10)
  };

  constructor(props) {
    super(props);
  }

  componentDidMount() {
    window.addEventListener('resize', this.updateDimensions);
    this.setState(state => ({
      screenshots: this.props.screenshots.map(screenshot => ({
        original: ('https://artifacts.tcstage.mozaws.net/' + this.props.taskId + '/' + this.props.runId + '/' + screenshot.name),
        originalAlt: (screenshot.name.split('/').pop().replace(/\.[^/.]+$/, '').replace('-', ' ')),
        originalTitle: (screenshot.name.split('/').pop().replace(/\.[^/.]+$/, '').replace('-', ' ')),
        thumbnail: ('https://artifacts.tcstage.mozaws.net/' + this.props.taskId + '/' + this.props.runId + '/' + screenshot.name.replace('/full/', '/thumbnail/').replace('.png', '-64x48.png')),
        thumbnailAlt: (screenshot.name.split('/').pop().replace(/\.[^/.]+$/, '').replace('-', ' ')),
        thumbnailTitle: (screenshot.name.split('/').pop().replace(/\.[^/.]+$/, '').replace('-', ' '))
      }))
    }));
  }

  updateDimensions = () => {
    if (window.innerWidth < 960) {
      this.setState(state => ({
        thumbnailPosition: 'bottom',
        galleryWidth: 640
      }));
    } else {
      this.setState(state => ({
        thumbnailPosition: 'left',
        galleryWidth: (640 + 48 + 10)
      }));
    }
  };

  componentWillUnmount() {
    window.removeEventListener('resize', this.updateDimensions);
  }

  render() {
    return (
      <div style={{width: '' + this.state.galleryWidth + 'px'}}>
        <ImageGallery items={this.state.screenshots} startIndex={(this.state.screenshots.length - 1)} thumbnailPosition={this.state.thumbnailPosition} />
      </div>
    );
  }
}

export default Screenshots;