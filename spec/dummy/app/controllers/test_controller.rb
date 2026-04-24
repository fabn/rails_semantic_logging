class TestController < ApplicationController
  def index
    logger.info('Test log from controller')
    render json: { status: 'ok' }
  end
end
