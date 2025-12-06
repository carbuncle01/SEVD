import cv2
import os
import argparse
from tqdm import tqdm
import re

def natural_sort_key(s):
    """
    "abc123xyz" -> ["abc", 123, "xyz"] のように自然なソート順のためのキーを生成
    """
    return [int(text) if text.isdigit() else text.lower()
            for text in re.split('([0-9]+)', s)]

def create_video_from_pngs(image_folder, output_video_path, fps):
    """
    指定されたフォルダ内のPNG画像から動画を作成する (変更なし)
    """
    
    # フォルダ内のPNGファイルを取得
    try:
        images = [img for img in os.listdir(image_folder) if img.endswith(".png")]
        if not images:
            return # PNGがなければ何もしない
            
        # ファイル名を自然な順序（例: 1, 2, ..., 10, 11）でソート
        images.sort(key=natural_sort_key)

    except FileNotFoundError:
        print(f"エラー: ディレクトリが見つかりません: {image_folder}")
        return
    except Exception as e:
        print(f"エラー: ファイルリスト取得中に問題発生 {image_folder}: {e}")
        return

    # 最初の画像を読み込んでサイズを取得
    try:
        first_image_path = os.path.join(image_folder, images[0])
        frame = cv2.imread(first_image_path)
        if frame is None:
            print(f"エラー: 画像を読み込めません: {first_image_path}")
            return
        height, width, layers = frame.shape
    except Exception as e:
        print(f"エラー: 最初の画像の読み込みに失敗: {first_image_path}: {e}")
        return

    # VideoWriterを初期化 (MP4コーデック)
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    
    # 出力先ディレクトリが存在することを確認
    os.makedirs(os.path.dirname(output_video_path), exist_ok=True)
    
    video_writer = cv2.VideoWriter(output_video_path, fourcc, fps, (width, height))

    if not video_writer.isOpened():
        print(f"エラー: VideoWriterを開けません: {output_video_path}")
        return

    # tqdmで進捗を表示しながら画像を動画に書き込む
    desc = f"Creating: {os.path.basename(output_video_path)}"
    for image_name in tqdm(images, desc=desc, leave=False):
        image_path = os.path.join(image_folder, image_name)
        frame = cv2.imread(image_path)
        if frame is not None:
            video_writer.write(frame)
        else:
            print(f"警告: フレームをスキップ (読み込み失敗): {image_path}")

    # リソースを解放
    video_writer.release()

def main():
    parser = argparse.ArgumentParser(description="指定された単一シーケンス内のPNGシーケンスから動画を生成します。")
    parser.add_argument("sequence_dir", type=str, 
                        help="対象のシーケンス・ディレクトリ (例: ./20251028_165216_1_1/001_Town01_Opt_ClearNoon)")
    parser.add_argument("--fps", type=float, default=10.0, 
                        help="出力動画のFPS (デフォルト: 10.0)")
    parser.add_argument("--output_dir", type=str, default="videos", 
                        help="動画の出力先ベースディレクトリ (デフォルト: 'videos'。シーケンスディレクトリの親階層に作成)")
    
    args = parser.parse_args()

    sequence_dir = os.path.normpath(args.sequence_dir)
    fps = args.fps

    if not os.path.isdir(sequence_dir):
        print(f"エラー: 指定されたディレクトリが見つかりません: {sequence_dir}")
        return

    sequence_name = os.path.basename(sequence_dir) # 例: 001_Town01_Opt_ClearNoon
    
    # --- 出力先の決定ロジックを変更 ---
    # デフォルトでは、指定されたシーケンスディレクトリの親階層に、
    # 'videos/シーケンス名/' というフォルダを作成します。
    if os.path.isabs(args.output_dir):
        output_base_dir = os.path.join(args.output_dir, sequence_name)
    else:
        # sequence_dirの親ディレクトリ（データセットのルート）を取得
        root_dir = os.path.dirname(sequence_dir)
        if not root_dir: # './001_...' のように指定された場合
            root_dir = "."
        output_base_dir = os.path.join(root_dir, args.output_dir, sequence_name)

    os.makedirs(output_base_dir, exist_ok=True)
    print(f"対象シーケンス: {sequence_dir}")
    print(f"動画の出力先: {os.path.abspath(output_base_dir)}")
    print(f"設定FPS: {fps}")

    # --- スキャン対象の収集ロジックを変更 ---
    # 指定されたシーケンスディレクトリの *直下* のみスキャン
    folders_to_process = []
    try:
        for sensor_dir_name in os.listdir(sequence_dir):
            sensor_dir_path = os.path.join(sequence_dir, sensor_dir_name)
            
            # ディレクトリでなければスキップ
            if not os.path.isdir(sensor_dir_path):
                continue
            
            # ディレクトリ内に .png があるかチェック
            try:
                if any(f.endswith(".png") for f in os.listdir(sensor_dir_path)):
                    folders_to_process.append(sensor_dir_path)
            except OSError:
                # 権限エラーなどで読めない場合はスキップ
                continue
                
    except FileNotFoundError:
        print(f"エラー: ディレクトリへのアクセス中に問題発生: {sequence_dir}")
        return

    if not folders_to_process:
        print("PNGファイルを含むセンサーディレクトリが見つかりませんでした。")
        return

    print(f"\n合計 {len(folders_to_process)} 個の画像シーケンスを動画に変換します。")

    # 全体の進捗バー用
    for image_folder in tqdm(folders_to_process, desc="Total Progress"):
        
        # --- 出力ファイル名の決定ロジックを変更 ---
        # 例: .../001_.../rgb_camera-front -> rgb_camera-front.mp4
        sensor_name = os.path.basename(image_folder)
        output_filename = sensor_name + ".mp4"
        output_video_path = os.path.join(output_base_dir, output_filename)

        # 動画作成関数の呼び出し
        create_video_from_pngs(image_folder, output_video_path, fps)

    print(f"\nすべての処理が完了しました。動画は {os.path.abspath(output_base_dir)} に保存されました。")

if __name__ == "__main__":        
    main()